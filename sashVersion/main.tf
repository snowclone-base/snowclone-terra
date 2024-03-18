provider "aws" {
  # region     = "us-east-1"
  region = "us-west-2"
}
# provision service discovery namespace
resource "aws_service_discovery_http_namespace" "snowclone4" {
  name        = "snowcloneSD"
  description = "example"
}

# provision cluster & capacity providers
resource "aws_ecs_cluster" "snowclone4" {
  name = "snowclone4"

  service_connect_defaults {
    namespace = aws_service_discovery_http_namespace.snowclone4.arn
  }
}

resource "aws_ecs_cluster_capacity_providers" "snowclone4" {
  cluster_name = aws_ecs_cluster.snowclone4.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 50
    capacity_provider = "FARGATE"
  }
}

# # provision security groups
# resource "aws_security_group" "allow_all" {
#   name        = "allow_all_traffic"
#   description = "Security group that allows all inbound and outbound traffic"
#   vpc_id      = aws_default_vpc.default_vpc.id

#   ingress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1" # -1 means all protocols
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1" # -1 means all protocols
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }

# Create a security group for the load balancer:
resource "aws_security_group" "allow_all" {
  name        = "lb_sg"
  description = "testing out ingress and egress in tf "
  vpc_id      = "${aws_default_vpc.default_vpc.id}"
  tags = {
    Name = "example"
  }
}

# Ingress rule for HTTP all the way to psql calls
resource "aws_vpc_security_group_ingress_rule" "allow_all" {
  security_group_id = aws_security_group.allow_all.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = -1
  # cidr_ipv4   = "0.0.0.0/0"
  # from_port   = 80
  # ip_protocol = "tcp"
  # to_port     = 5432
}


# Egress rule
resource "aws_vpc_security_group_egress_rule" "allow_all" {
  security_group_id = aws_security_group.allow_all.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = -1
}

# provision ALB
resource "aws_lb" "snowclone4-alb" {
  name               = "snowclone4-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_all.id] # need to make SGs
  subnets            = [aws_default_subnet.default_subnet_a.id, aws_default_subnet.default_subnet_b.id]
}

# set up target group
resource "aws_lb_target_group" "tg-postgrest" {
  name        = "tg-postgrest"
  port        = "80"
  protocol    = "HTTP"
  vpc_id      = aws_default_vpc.default_vpc.id
  target_type = "ip"
}

# set up ALB listener
resource "aws_lb_listener" "snowclone4-alb-listener" {
  load_balancer_arn = aws_lb.snowclone4-alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg-postgrest.arn
  }
}

# postgres task definition
resource "aws_ecs_task_definition" "postgresDB" {
  family                   = "postgresDB"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512

  container_definitions = jsonencode([
    {
      name   = "postgresDB-container"
      image  = "snowclone/postgres"
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
      "healthcheck" : {
        "command" : ["CMD-SHELL", "pg_isready -U postgres"],
        "interval" : 5,
        "timeout" : 5,
        "retries" : 5
      },
    }
  ])
}

# postgrest task definition
resource "aws_ecs_task_definition" "postgrest-sc" {
  family                   = "postgrest-sc"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512

  container_definitions = jsonencode([
    {
      name   = "postgrest-sc-container"
      image  = "snowclone/postg-rest"
      memory = 512
      cpu    = 256
      portMappings = [
        {
          name="postgrest-port-3000"
          containerPort = 3000
        }
      ]
      essential = true
      environment = [
        { "name" : "PGRST_DB_URI", "value" : "postgres://authenticator:mysecretpassword@pg-service:5432/postgres" },
        { "name" : "PGRST_DB_SCHEMA", "value" : "api" },
        { "name" : "PGRST_DB_ANON_ROLE", "value" : "web_anon" },
        { "name" : "PGRST_OPENAPI_SERVER_PROXY_URI", "value" : "http://localhost:3000" },
        { "name" : "PGRST_ADMIN_SERVER_PORT", "value" : "3001"}
      ],
      "healthcheck" : {
        "command" : ["CMD-SHELL", "curl -f http://localhost:3001/ready || exit 1"],
        "interval" : 5,
        "timeout" : 5,
        "startPeriod" : 10,
        "retries" : 5
      },
    }
  ])
}

# provision postgres service
resource "aws_ecs_service" "pg-service" {
  name            = "pg-service"
  cluster         = aws_ecs_cluster.snowclone4.id
  task_definition = aws_ecs_task_definition.postgresDB.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  #   load_balancer {
  #     target_group_arn = aws_lb_target_group.tg-postgres-terra.arn # Reference the target group
  #     container_name   = "postgres-terra-container"
  #     container_port   = 5432 # Specify the container port
  #   }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.snowclone4.arn

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

# provision postgrest service
resource "aws_ecs_service" "postgrest-service" {
  name            = "postgrest-service"
  cluster         = aws_ecs_cluster.snowclone4.id
  task_definition = aws_ecs_task_definition.postgrest-sc.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  load_balancer {
    target_group_arn = aws_lb_target_group.tg-postgrest.arn # Reference the target group
    container_name   = "postgrest-sc-container"
    container_port   = 3000 # Specify the container port
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.snowclone4.arn

    service {
      client_alias {
        port     = 3000
        dns_name = "postgrest-service"
      }
      discovery_name = "postgrest-service"
      port_name      = "postgrest-port-3000"
    }
  }

  network_configuration {
    subnets          = [aws_default_subnet.default_subnet_a.id, aws_default_subnet.default_subnet_b.id]
    assign_public_ip = true                              # Provide the containers with public IPs
    security_groups  = [aws_security_group.allow_all.id] # Set up the security group
  }
}

#Log the load balancer app URL
output "app_url" {
  value = aws_lb.snowclone4-alb.dns_name
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
