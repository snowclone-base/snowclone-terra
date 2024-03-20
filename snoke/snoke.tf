provider "aws" {
  region     = "us-west-2"
}

# create cloud map namespace
resource "aws_service_discovery_http_namespace" "snoke" {
  name        = "snoke"
  description = "snoke"
}

# provision cluster & capacity providers
resource "aws_ecs_cluster" "snoke" {
  name = "snoke"

  service_connect_defaults {
    namespace = aws_service_discovery_http_namespace.snoke.arn
  }
}

resource "aws_ecs_cluster_capacity_providers" "snoke" {
  cluster_name = aws_ecs_cluster.snoke.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 50
    capacity_provider = "FARGATE"
  }
}

# provision security groups
resource "aws_security_group" "allow_all" {
  name        = "lb_sg"
  description = "testing out ingress and egress in tf "
  vpc_id      = aws_default_vpc.default_vpc.id
  tags = {
    Name = "openBothWays"
  }
}

# Ingress rule
resource "aws_vpc_security_group_ingress_rule" "allow_all" {
  security_group_id = aws_security_group.allow_all.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = -1 #all protocols
}


# Egress rule
resource "aws_vpc_security_group_egress_rule" "allow_all" {
  security_group_id = aws_security_group.allow_all.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = -1 #all protocols
}

# provision ALB
resource "aws_lb" "snoke-alb" {
  name               = "snoke-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_all.id] # need to make SGs
  subnets            = [aws_default_subnet.default_subnet_a.id, aws_default_subnet.default_subnet_b.id]
}

# set up target groups
resource "aws_lb_target_group" "tg-postgrest" {
  name        = "tg-postgrest"
  port        = "3000"
  protocol    = "HTTP"
  vpc_id      = aws_default_vpc.default_vpc.id
  target_type = "ip"
}

resource "aws_lb_target_group" "tg-eventserver" {
  name        = "tg-eventserver"
  port        = "8080"
  protocol    = "HTTP"
  vpc_id      = aws_default_vpc.default_vpc.id
  target_type = "ip"
}

# set up ALB listener
resource "aws_lb_listener" "snoke-alb-listener" {
  load_balancer_arn = aws_lb.snoke-alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg-postgrest.arn
  }
}

# set up routes
resource "aws_lb_listener_rule" "realtime" {
  listener_arn = aws_lb_listener.snoke-alb-listener.arn
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

# postgres task definition
resource "aws_ecs_task_definition" "postgres" {
  family                   = "postgres"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512

  container_definitions = jsonencode([
    {
      name   = "postgres-container"
      image  = "snowclone/postgres:amd64-test"
      memory = 512
      cpu    = 256
      portMappings = [
        {
          name          = "pg-port-5432"
          containerPort = 5432
        }
      ]
      essential = true
      environment = [
        {
          name  = "POSTGRES_DB"
          value = "postgres"
        },
        {
          name  = "POSTGRES_PASSWORD"
          value = "postgres"
        },
        {
          name  = "POSTGRES_USER"
          value = "postgres"
        },
      ]
      healthcheck = {
        command  = ["CMD-SHELL", "pg_isready -U postgres"]
        interval = 5
        timeout  = 5
        retries  = 5
      }
    }
  ])
}

# provision postgres service
resource "aws_ecs_service" "pg-service" {
  name            = "pg-service"
  cluster         = aws_ecs_cluster.snoke.id
  task_definition = aws_ecs_task_definition.postgres.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  service_connect_configuration {
    enabled   = true
    namespace = "snoke"

    service {
      client_alias {
        port     = 5432
        dns_name = "pg-service"
      }
      discovery_name = "pg-service"
      port_name      = "pg-port-5432"
    }
  }

  network_configuration {
    subnets          = [aws_default_subnet.default_subnet_a.id, aws_default_subnet.default_subnet_b.id]
    assign_public_ip = true                              # Provide the containers with public IPs
    security_groups  = [aws_security_group.allow_all.id] # Set up the security group
  }
}

# postgrest task definition
resource "aws_ecs_task_definition" "postgrest" {
  family                   = "postgrest"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512

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
        { name = "PGRST_DB_URI", value = "postgres://authenticator:mysecretpassword@pg-service:5432/postgres" },
        { name = "PGRST_DB_SCHEMA", value = "api" },
        { name = "PGRST_DB_ANON_ROLE", value = "web_anon" },
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
    },
    {
      name  = "eventserver-container"
      image = "snowclone/eventserver:2.0.0"
      # memory = 512
      # cpu    = 256
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
        { name = "PG_HOST", value = "pg-service" },
        { name = "PG_PORT", value = "5432" },
        { name = "PG_DATABASE", value = "postgres" }
      ]
      healthcheck = {
        command     = ["CMD-SHELL", "curl http://localhost:8080/ || exit 1"], # Example health check command
        interval    = 5,
        timeout     = 5,
        startPeriod = 10,
        retries     = 5
      }
    }
  ])
}

# provision postgrest service
resource "aws_ecs_service" "postgrest-service" {
  name            = "postgrest-service"
  cluster         = aws_ecs_cluster.snoke.id
  task_definition = aws_ecs_task_definition.postgrest.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  load_balancer {
    target_group_arn = aws_lb_target_group.tg-postgrest.arn # Reference the target group
    container_name   = "postgrest-container"
    container_port   = 3000 # Specify the container port.
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg-eventserver.arn # Reference the target group
    container_name   = "eventserver-container"
    container_port   = 8080 # Specify the container port
  }

  service_connect_configuration {
    enabled   = true
    namespace = "snoke"
  }

  network_configuration {
    subnets          = [aws_default_subnet.default_subnet_a.id, aws_default_subnet.default_subnet_b.id]
    assign_public_ip = true                              # Provide the containers with public IPs
    security_groups  = [aws_security_group.allow_all.id] # Set up the security group
  }
}

# VPC and private subnets
resource "aws_default_vpc" "default_vpc" {}

# Provide references to your default subnets
resource "aws_default_subnet" "default_subnet_a" {
  # Use your own region here but reference to subnet 1a
  availability_zone = "us-west-2a"
}

resource "aws_default_subnet" "default_subnet_b" {
  # Use your own region here but reference to subnet 1b
  availability_zone = "us-west-2b"
}

output "app_url" {
  value = aws_lb.snoke-alb.dns_name
}