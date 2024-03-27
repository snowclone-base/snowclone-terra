provider "aws" {
  region = "us-west-2"
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

# attach ECS task permissions to role
resource "aws_iam_role_policy_attachment" "ecs-task-permissions" {
  role       = aws_iam_role.ecsTaskExecutionRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

###################################################################################
#                           New RDS Section                                       #
###################################################################################

# create RDS
resource "aws_db_instance" "snoke-db" {
  allocated_storage      = 10
  apply_immediately      = true
  db_name                = "postgres"
  engine                 = "postgres"
  engine_version         = "16.2"
  instance_class         = "db.t3.micro"
  parameter_group_name   = aws_db_parameter_group.education.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true
  username               = "postgres"
  password               = "postgres"
  publicly_accessible    = true
}

# create parameter group for db
resource "aws_db_parameter_group" "education" {
  name   = "education"
  family = "postgres16"

  parameter {
    name  = "log_connections"
    value = "1"
  }
}
# create function call to invoke config
resource "null_resource" "setup_db" {
  depends_on = [aws_db_instance.snoke-db] #wait for the db to be ready
  provisioner "local-exec" {

    command = "psql -h ${aws_db_instance.snoke-db.address} -p 5432 -U \"postgres\" -d postgres -f \"./apiSchema.sql\""

    environment = {
      PGPASSWORD = "postgres"
    }
  }
}

resource "aws_security_group" "rds" {
  name   = "education_rds"
  vpc_id = aws_default_vpc.default_vpc.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "education_rds"
  }
}


######################################################################################
#                           END New RDS Section                                      #
######################################################################################

# provision cluster & capacity providers
resource "aws_ecs_cluster" "snoke" {
  name = "snoke"

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

# Create a CloudWatch Logs group
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/snoke"
  retention_in_days = 30 # Adjust retention policy as needed
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

resource "aws_lb_listener_rule" "schema-upload" {
  listener_arn = aws_lb_listener.snoke-alb-listener.arn
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
        { name = "PGRST_DB_URI", value = "postgres://authenticator:mysecretpassword@${aws_db_instance.snoke-db.endpoint}/postgres" },
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
          awslogs-region        = "us-west-2"
          awslogs-stream-prefix = "postgrest"
        }
      }
    },
    {
      name  = "eventserver-container"
      image = "snowclone/eventserver:RDStest" # "snowclone/eventserver:3.0.1"
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
        { name = "DATABASE_URL", value = "postgresql://postgres:postgres@${aws_db_instance.snoke-db.endpoint}/postgres" }
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
          awslogs-region        = "us-west-2"
          awslogs-stream-prefix = "event-server"
        }
      }
    },
    {
      name  = "schema-server-container"
      image = "snowclone/schema-server:RDStest" #"snowclone/schema-server:2.0.2"
      # memory = 512
      # cpu    = 256
      portMappings = [
        {
          name          = "schema-server-port-5175"
          containerPort = 5175
        }
      ]
      essential = true
      environment = [
        { name = "DATABASE_URL", value = "postgresql://postgres:postgres@${aws_db_instance.snoke-db.endpoint}/postgres" },
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
          awslogs-region        = "us-west-2"
          awslogs-stream-prefix = "schema-server"
        }
      }
    }
  ])
}

# provision api service
resource "aws_ecs_service" "api-service" {
  name            = "api-service"
  cluster         = aws_ecs_cluster.snoke.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  depends_on      = [aws_db_instance.snoke-db] #wait for the db to be ready

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

  load_balancer {
    target_group_arn = aws_lb_target_group.tg-schema-server.arn # Reference the target group
    container_name   = "schema-server-container"
    container_port   = 5175 # Specify the container port
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

output "db_url" {
  value = aws_db_instance.snoke-db.endpoint
}
