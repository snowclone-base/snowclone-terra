provider "aws" {
  region = var.region
}

# create ECS task execution role
resource "aws_iam_role" "ecsTaskExecutionRole" {
  name = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2008-10-17",
    Statement = [
      {
        Sid    = "",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# attach ECS task permissions to current role
resource "aws_iam_role_policy_attachment" "ecs-task-permissions" {
  role       = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

###################################################################################
#                           New RDS Section                                       #
###################################################################################

# create RDS
resource "aws_db_instance" "rds-db" {
  allocated_storage      = 10
  apply_immediately      = true
  db_name                = "postgres"
  engine                 = "postgres"
  engine_version         = "14"
  instance_class         = "db.t3.micro"
  parameter_group_name   = aws_db_parameter_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true
  username               = "postgres"
  password               = "postgres"

}

# create parameter group for db
resource "aws_db_parameter_group" "rds" {
  name   = var.project_name
  family = "postgres14"

  parameter {
    name  = "log_connections"
    value = "1"
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}_rds"
  vpc_id      = aws_default_vpc.default_vpc.id
  description = "only reachable from api servers"
  tags = {
    Name = "${var.project_name}_rds"
  }
}

# DB ingress rule from API
resource "aws_vpc_security_group_ingress_rule" "allow-api-to-db" {
  security_group_id = aws_security_group.rds.id

  from_port                    = 5432
  ip_protocol                  = "tcp"
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.api_servers.id
}

# DB egress rule to API
resource "aws_vpc_security_group_egress_rule" "allow-db-to-api" {
  security_group_id = aws_security_group.rds.id

  from_port                    = 5432
  ip_protocol                  = "tcp"
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.api_servers.id
}

######################################################################################
#                           END New RDS Section                                      #
######################################################################################

# provision cluster & capacity providers
resource "aws_ecs_cluster" "project_name" {
  name = var.project_name

}

resource "aws_ecs_cluster_capacity_providers" "project_name" {
  cluster_name = aws_ecs_cluster.project_name.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 50
    capacity_provider = "FARGATE"
  }
}

# Create a CloudWatch Logs group
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 30 # Adjust retention policy as needed
}

# provision security group for load balancer
resource "aws_security_group" "alb_web_traffic" {
  name        = "lb_sg"
  description = "only allow http and https inbound. allow all outbound"
  vpc_id      = aws_default_vpc.default_vpc.id
  tags = {
    Name = "${var.project_name}_internet_facing_alb"
  }
}

# lb Ingress rules
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.alb_web_traffic.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  ip_protocol = "tcp"
  to_port     = 80
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.alb_web_traffic.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  ip_protocol = "tcp"
  to_port     = 443
}

# lb Egress rules
resource "aws_vpc_security_group_egress_rule" "allow_all" {
  security_group_id = aws_security_group.alb_web_traffic.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = -1 #all protocols
}

# API servers security group
resource "aws_security_group" "api_servers" {
  name        = "${var.project_name}_api_sg"
  description = "only reachable from lb and db. NAT allows image pulls"
  vpc_id      = aws_default_vpc.default_vpc.id
  tags = {
    Name = "${var.project_name}_api_sg"
  }
}

# API ingress rule from alb
resource "aws_vpc_security_group_ingress_rule" "alb-to-api" {
  security_group_id = aws_security_group.api_servers.id

  ip_protocol                  = -1
  referenced_security_group_id = aws_security_group.alb_web_traffic.id
}

# API ingress rule from db
resource "aws_vpc_security_group_ingress_rule" "db-to-api" {
  security_group_id = aws_security_group.api_servers.id

  from_port                    = 5432
  ip_protocol                  = "tcp"
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.rds.id
}

# API egress rule. Wide open to allow for image pulls. 
resource "aws_vpc_security_group_egress_rule" "allow-all" {
  security_group_id = aws_security_group.api_servers.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = -1
}


# Create an SSL/TLS certificate
resource "aws_acm_certificate" "cert" {
  domain_name       = "*.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_route53_zone" "zone" {
  name         = var.domain_name
  private_zone = false
}

resource "aws_route53_record" "record" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.zone.zone_id
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.record : record.fqdn]
}

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
  name        = "tg-postgrest"
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
  name        = "tg-eventserver"
  port        = "8080"
  protocol    = "HTTP"
  vpc_id      = aws_default_vpc.default_vpc.id
  target_type = "ip"
}

resource "aws_lb_target_group" "tg-schema-server" {
  name        = "tg-schema-server"
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

# Step 2: Configure the ALB listener with HTTPS
resource "aws_lb_listener" "alb-listener-https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.cert.arn

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

# api task definition
resource "aws_ecs_task_definition" "api" {
  family                   = "api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecsTaskExecutionRole.arn

  container_definitions = jsonencode([
    {
      name  = "eventserver-container"
      image = "snowclone/eventserver:3.0.1"
      portMappings = [
        {
          name          = "eventserver-port-8080"
          containerPort = 8080
        }
      ]
      essential = true
      environment = [
        { name = "PG_USER", value = "postgres" },
        { name = "PG_PASSWORD", value = "postgres" },
        { name = "PG_HOST", value = "${aws_db_instance.rds-db.address}" },
        { name = "PG_PORT", value = "5432" },
        { name = "PG_DATABASE", value = "postgres" }
        # { name = "DATABASE_URL", value = "postgresql://postgres:postgres@${aws_db_instance.rds-db.endpoint}/postgres" }
      ]
      healthcheck = {
        command     = ["CMD-SHELL", "curl http://localhost:8080/ || exit 1"], # Example health check command
        interval    = 5,
        timeout     = 5,
        startPeriod = 10,
        retries     = 5
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_logs.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "event-server"
        }
      }
    },
    {
      name  = "schema-server-container"
      image = "snowclone/schema-server:2.0.2"

      portMappings = [
        {
          name          = "schema-server-port-8080"
          containerPort = 5175
        }
      ]
      essential = true
      environment = [
        { name = "DATABASE_URL", value = "postgresql://postgres:postgres@${aws_db_instance.rds-db.endpoint}/postgres" },
        { name = "API_TOKEN", value = "helo" },
      ]
      healthcheck = {
        command     = ["CMD-SHELL", "curl http://localhost:5175/V1/api || exit 1"], # Example health check command
        interval    = 5,
        timeout     = 5,
        startPeriod = 10,
        retries     = 5
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_logs.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "schema-server"
        }
      }
    }
  ])
}

# postgrest task definition
resource "aws_ecs_task_definition" "postgrest" {
  family                   = "postgrest"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecsTaskExecutionRole.arn

  container_definitions = jsonencode([
    {
      name  = "postgrest-container"
      image = "snowclone/postg-rest:latest"
      #   memory = 512
      #   cpu    = 256
      portMappings = [
        {
          name          = "postgrest-port-3000"
          containerPort = 3000
        }
      ]
      essential = true
      environment = [
        { name = "PGRST_DB_URI", value = "postgres://authenticator:mysecretpassword@${aws_db_instance.rds-db.endpoint}/postgres" },
        { name = "PGRST_DB_SCHEMA", value = "api" },
        { name = "PGRST_DB_ANON_ROLE", value = "anon" },
        { name = "PGRST_OPENAPI_SERVER_PROXY_URI", value = "http://localhost:3000" },
        { name = "PGRST_ADMIN_SERVER_PORT", value = "3001" },
        { name = "PGRST_JWT_SECRET", value = "O9fGlY0rDdDyW1SdCTaoqLmgQ2zZeCz6" } #added so we could test adding to db
      ],
      healthcheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:3001/ready || exit 1"]
        interval    = 5
        timeout     = 5
        startPeriod = 10
        retries     = 5
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_logs.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "postgrest"
        }
      }
    }
  ])
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
    target_group_arn = aws_lb_target_group.tg-schema-server.arn
    container_name   = "schema-server-container"
    container_port   = 5175 # Specify the container port
  }

  network_configuration {
    subnets          = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
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
    target_group_arn = aws_lb_target_group.tg-postgrest.arn
    container_name   = "postgrest-container"
    container_port   = 3000 # Specify the container port.
  }

  network_configuration {
    subnets          = [aws_subnet.private_subnet_a.id, aws_subnet.private_subnet_b.id]
    assign_public_ip = false
    security_groups  = [aws_security_group.api_servers.id]
  }
}

# VPC and private subnets
resource "aws_default_vpc" "default_vpc" {}

# new route table for private subnet
resource "aws_route_table" "private" {
  vpc_id = aws_default_vpc.default_vpc.id

  route {
    cidr_block = "172.31.0.0/16"
    gateway_id = "local"
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat.id
  }
}

# private subnet a
resource "aws_subnet" "private_subnet_a" {
  cidr_block        = "172.31.253.0/24"
  vpc_id            = aws_default_vpc.default_vpc.id
  availability_zone = "${var.region}a"
}

#private subnet b
resource "aws_subnet" "private_subnet_b" {
  cidr_block        = "172.31.255.0/24"
  vpc_id            = aws_default_vpc.default_vpc.id
  availability_zone = "${var.region}b"
}

#associate private subnets with private route table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.private_subnet_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.private_subnet_b.id
  route_table_id = aws_route_table.private.id
}

# create elastic ip to be used by NAT
resource "aws_eip" "nat" {
  domain = "vpc"
}

#create NAT gateway
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_default_subnet.default_subnet_a.id
}


# default public subnets
resource "aws_default_subnet" "default_subnet_a" {
  availability_zone = "${var.region}a"
}

resource "aws_default_subnet" "default_subnet_b" {
  availability_zone = "${var.region}b"
}

output "app_url" {
  value = "${var.project_name}.${var.domain_name}"
}
