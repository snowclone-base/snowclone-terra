# provision ALB
resource "aws_lb" "alb" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_web_traffic.id]
  subnets            = [aws_default_subnet.default_subnet_a.id, aws_default_subnet.default_subnet_b.id]
}

data "aws_lb" "alb" {
  name = aws_lb.alb.name

  depends_on = [aws_lb.alb]
}

data "aws_route53_zone" "zone" {
  zone_id = var.aws_route53_zone_id
}

# Create Route 53 record
resource "aws_route53_record" "alb_record" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = "${var.project_name}.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [aws_lb.alb.dns_name]
}

# set up target groups
resource "aws_lb_target_group" "tg-postgrest" {
  name        = "${var.project_name}-tg-postgrest"
  port        = "3000"
  protocol    = "HTTP"
  vpc_id      = aws_default_vpc.default_vpc.id
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/ready"
    port                = "3001"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group" "tg-eventserver" {
  name        = "${var.project_name}-tg-eventserver"
  port        = "8080"
  protocol    = "HTTP"
  vpc_id      = aws_default_vpc.default_vpc.id
  target_type = "ip"
}

resource "aws_lb_target_group" "tg-schema-server" {
  name        = "${var.project_name}-tg-schema-server"
  port        = "5175"
  protocol    = "HTTP"
  vpc_id      = aws_default_vpc.default_vpc.id
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    path                = "/V1/api"
    port                = "traffic-port"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }
}

# Set up ALB listener for HTTP traffic
resource "aws_lb_listener" "alb-listener-http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

data "aws_acm_certificate" "cert" {
  domain = "*.${var.domain_name}"
}

# Step 2: Configure the ALB listener with HTTPS
resource "aws_lb_listener" "alb-listener-https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = data.aws_acm_certificate.cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg-postgrest.arn
  }
}

# set up routes
resource "aws_lb_listener_rule" "realtime" {
  listener_arn = aws_lb_listener.alb-listener-https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg-eventserver.arn
  }

  condition {
    path_pattern {
      values = ["/realtime"]
    }
  }
}

resource "aws_lb_listener_rule" "schema-upload" {
  listener_arn = aws_lb_listener.alb-listener-https.arn
  priority     = 101

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg-schema-server.arn
  }

  condition {
    path_pattern {
      values = ["/schema"]
    }
  }
}

# provision api service
resource "aws_ecs_service" "api-service" {
  name            = "api-service"
  cluster         = aws_ecs_cluster.project_name.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  depends_on      = [aws_db_instance.rds-db] #wait for the db to be ready

  load_balancer {
    target_group_arn = aws_lb_target_group.tg-eventserver.arn # Reference the target group
    container_name   = "eventserver-container"
    container_port   = 8080 # Specify the container port
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg-schema-server.arn # Reference the target group
    container_name   = "schema-server-container"
    container_port   = 5175 # Specify the container port
  }

  network_configuration {
    # update
    subnets          = [data.aws_subnet.private_subnet_a.id, data.aws_subnet.private_subnet_b.id]
    assign_public_ip = false
    security_groups  = [aws_security_group.api_servers.id]
  }
}

# provision postgrest service
resource "aws_ecs_service" "postgrest-service" {
  name            = "postgrest-service"
  cluster         = aws_ecs_cluster.project_name.id
  task_definition = aws_ecs_task_definition.postgrest.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  depends_on      = [aws_db_instance.rds-db] #wait for the db to be ready

  load_balancer {
    target_group_arn = aws_lb_target_group.tg-postgrest.arn # Reference the target group
    container_name   = "postgrest-container"
    container_port   = 3000 # Specify the container port.
  }

  network_configuration {
    # update subnet declaration
    subnets          = [data.aws_subnet.private_subnet_a.id, data.aws_subnet.private_subnet_b.id]
    assign_public_ip = false
    security_groups  = [aws_security_group.api_servers.id]
  }
}

output "app_url" {
  value = "${var.project_name}.${var.domain_name}"
}

terraform {
  backend "s3" {}
}
