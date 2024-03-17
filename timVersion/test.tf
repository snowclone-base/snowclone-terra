terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
}

# Provide a reference to your default VPC
resource "aws_default_vpc" "default_vpc" {
}

# Provide references to your default subnet(s)
resource "aws_default_subnet" "default_subnet_a" {
  # Use your own region here but reference to subnet 1a
  availability_zone = "us-west-2a"
}

# Create a Cluster
resource "aws_ecs_cluster" "my_cluster" {
  name = "snowclone-cluster"
}

# Create a security group for the load balancer:
resource "aws_security_group" "load_balancer_security_group" {
  name        = "lb_sg"
  description = "testing out vpc_security_group_ingress_rule in tf "
  vpc_id      = "${aws_default_vpc.default_vpc.id}"
  tags = {
    Name = "example"
  }
}

# Ingress rule for HTTP all the way to psql calls
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.load_balancer_security_group.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  ip_protocol = "tcp"
  to_port     = 5432
}


# Egress rule
resource "aws_vpc_security_group_egress_rule" "open" {
  security_group_id = aws_security_group.load_balancer_security_group.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = -1
}


# Create a load balancer 
resource "aws_alb" "network_load_balancer" {
  name               = "load-balancer-snowclone" #load balancer name
  load_balancer_type = "network"
  subnets = [ # Referencing the default subnet(s)
    "${aws_default_subnet.default_subnet_a.id}"
  ]
  # security group
  security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
}


# Configure Load Balancer with VPC networking

# postgREST Target group
resource "aws_lb_target_group" "postgREST" {
  name        = "postgREST-target-group"
  port        = 3000
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = "${aws_default_vpc.default_vpc.id}" # default VPC
}


# db Target group
resource "aws_lb_target_group" "db" {
  name        = "db-target-group"
  port        = 5432
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = "${aws_default_vpc.default_vpc.id}" # default VPC
}

# HTTP Listener
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = "${aws_alb.network_load_balancer.arn}" #  load balancer
  port              = "80"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.postgREST.arn}" # target group
  }
}


# Direct db TCP Listener
resource "aws_lb_listener" "db_tcp" {
  load_balancer_arn = "${aws_alb.network_load_balancer.arn}"
  port              = "5432"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.db.arn
  }
}

# Only allow traffic to containers from load balancer
resource "aws_security_group" "service_security_group" {
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # Only allowing traffic in from the load balancer security group
    security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


## Create a Task Definition
resource "aws_ecs_task_definition" "app" {
  family                   = "snowcloneApps" # Name your task
  container_definitions    = <<DEFINITION
  [
    {
      "name": "postgresDB",
      "image": "6esxh87qep2f6ksk/postgres-custom-init:latest",
      "essential": true,
      "environment": [
        {"name": "POSTGRES_PASSWORD", "value": "postgres"},
        {"name": "POSTGRES_USER", "value": "postgres"},
        {"name": "POSTGRES_DB", "value" : "postgres"}
      ],
      "healthcheck": {
        "command": ["CMD-SHELL", "pg_isready -U postgres"],
        "interval": 5,
        "timeout": 5,
        "retries": 5
      },
      "portMappings": [
        {
          "containerPort": 5432
        }
      ],
      "memory": 512,
      "cpu": 256
    },
    {
      "name": "postgREST",
      "image": "6esxh87qep2f6ksk/postgrest-curl:latest",
      "essential": true,
      "environment": [
        {"name": "PGRST_DB_URI", "value": "postgres://authenticator:mysecretpassword@localhost:5432/postgres"},
        {"name": "PGRST_DB_SCHEMA", "value": "api"},
        {"name": "PGRST_DB_ANON_ROLE", "value" : "web_anon"},
        {"name": "PGRST_OPENAPI_SERVER_PROXY_URI", "value" : "http://localhost:3000"},
        {"name": "PGRST_JWT_SECRET", "value" : "O9fGlY0rDdDyW1SdCTaoqLmgQ2zZeCz6"},
        {"name": "PGRST_ADMIN_SERVER_PORT", "value" : "3001"}
      ],
      "healthcheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:3001/ready || exit 1"],
        "interval": 5,
        "timeout": 5,
        "retries": 5
      },
      "dependsOn": [
        {
          "containerName": "postgresDB",
          "condition": "HEALTHY"
        }
      ],
      "portMappings": [
        {
          "containerPort": 3000
        },
        {
          "containerPort": 3001
        }
      ],
      "memory": 512,
      "cpu": 256
    }
  ]
  DEFINITION
  requires_compatibilities = ["FARGATE"] # use Fargate as the launch type
  network_mode             = "awsvpc"    # add the AWS VPN network mode as this is required for Fargate
  memory                   = 1024         # Specify the memory the container requires
  cpu                      = 512         # Specify the CPU the container requires
  # didn't need below bc my IAM user already had perms
  # execution_role_arn       = "${aws_iam_role.ecsTaskExecutionRole.arn}"
}

# Create an ECS Service:


resource "aws_ecs_service" "snowCloneService" {
  name            = "snowClone"     # Name the service
  cluster         = "${aws_ecs_cluster.my_cluster.id}"   # Reference the created Cluster
  task_definition = "${aws_ecs_task_definition.app.arn}" # Reference the task that the service will spin up
  launch_type     = "FARGATE"
  desired_count   = 1 # Set up the number of containers to 1

  #postgREST
  load_balancer {
    target_group_arn = "${aws_lb_target_group.postgREST.arn}" # Reference the target group
    container_name   = "postgREST" #"${aws_ecs_task_definition.app.family}"
    container_port   = 3000 # Specify the container port
  }

  #db
  load_balancer {
    target_group_arn = "${aws_lb_target_group.db.arn}" # Reference the target group
    container_name   = "postgresDB" #"${aws_ecs_task_definition.app.family}"
    container_port   = 5432 # Specify the container port
  }
  

  network_configuration {
    subnets          = ["${aws_default_subnet.default_subnet_a.id}"]
    assign_public_ip = true     # Provide the containers with public IPs
    security_groups  = ["${aws_security_group.service_security_group.id}"] # Set up the security group
  }
}

#Log the load balancer app URL
output "app_url" {
  value = aws_alb.network_load_balancer.dns_name
}

# ----------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------

# COMMENTED OUT STUFF

/*
# Create a default security group for non-pubic containers
resource "aws_default_security_group" "default" {
  vpc_id = aws_default_vpc.default_vpc.id

  ingress {
    protocol  = -1
    self      = true
    from_port = 0
    to_port   = 0
  }
}
*/

/* resource "aws_ecs_task_definition" "apiServers" {
  family                   = "apiServers" # Name your task
  container_definitions    = <<DEFINITION
  [
    {
      "name": "postgREST",
      "image": "postgrest/postgrest:latest",
      "essential": true,
      "environment": [
        {"name": "PGRST_DB_URI", "value": "postgres://authenticator:mysecretpassword@db:5432/postgres"},
        {"name": "PGRST_DB_SCHEMA", "value": "api"},
        {"name": "PGRST_DB_ANON_ROLE", "value" : "web_anon"},
        {"name": "PGRST_OPENAPI_SERVER_PROXY_URI", "value" : "http://localhost:3000"},
        {"name": "PGRST_JWT_SECRET", "value" : "O9fGlY0rDdDyW1SdCTaoqLmgQ2zZeCz6"}
      ],
      "dependsOn": [
        {
          "containerName": "postgresDB",
          "condition": "HEALTHY"
        }
      ],
      "portMappings": [
        {
          "containerPort": 3000,
          #"hostPort": 3000
        }
      ],
      "memory": 512,
      "cpu": 256
    }
  ]
  DEFINITION
  requires_compatibilities = ["FARGATE"] # use Fargate as the launch type
  network_mode             = "awsvpc"    # add the AWS VPN network mode as this is required for Fargate
  memory                   = 512         # Specify the memory the container requires
  cpu                      = 256         # Specify the CPU the container requires
  # didn't need below bc my IAM user already had perms
  # execution_role_arn       = "${aws_iam_role.ecsTaskExecutionRole.arn}"
}
*/

/* resource "aws_ecs_service" "db_service" {
  name            = "snowclone-db-service"     # Name the service
  cluster         = "${aws_ecs_cluster.my_cluster.id}"   # Reference the created Cluster
  task_definition = "${aws_ecs_task_definition.database.arn}" # Reference the task that the service will spin up
  launch_type     = "FARGATE"
  desired_count   = 1 # Set up the number of containers to 1

  network_configuration {
    subnets          = ["${aws_default_subnet.default_subnet_a.id}", "${aws_default_subnet.default_subnet_b.id}"]
    assign_public_ip = true     # Provide the containers with public IPs
    security_groups  = ["${aws_security_group.service_security_group.id}"] # Set up the security group
    #security_groups  = ["${aws_default_security_group.default}"] # Set up the security group
  }
}
*/

/*

# Create a security group for the load balancer:
resource "aws_security_group" "load_balancer_security_group" {
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow traffic in from all sources
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
*/

/*
# Ingress rule for db
resource "aws_vpc_security_group_ingress_rule" "db" {
  security_group_id = aws_security_group.load_balancer_security_group.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 5432
  ip_protocol = "tcp"
  to_port     = 5432

}
*/

/*
# admin Target group
resource "aws_lb_target_group" "admin" {
  name        = "admin-target-group"
  port        = 5173
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = "${aws_default_vpc.default_vpc.id}" # default VPC
}
*/

/*
# Admin Listener
resource "aws_lb_listener" "admin_listener" {
  load_balancer_arn = "${aws_alb.application_load_balancer.arn}" #  load balancer
  port              = "5173"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.admin.arn}" # target group
  }
}
*/

/*
#admin lb from within service definition
  load_balancer {
    target_group_arn = "${aws_lb_target_group.admin.arn}" # Reference the target group
    container_name   = "db-admin" #"${aws_ecs_task_definition.app.family}"
    container_port   = 5173 # Specify the container port
  }

*/

/*
# container definition for db-admin. took out to save on data costs for spinning up demos
{
      "name": "db-admin",
      "image": "lukepow/relay-admin:latest",
      "essential": true,
      "dependsOn": [
        {
          "containerName": "postgresDB",
          "condition": "HEALTHY"
        }
      ],
      "portMappings": [
        {
          "containerPort": 5173
        }
      ],
      "memory": 512,
      "cpu": 256
    }
*/    

/*
# Second default subnet
resource "aws_default_subnet" "default_subnet_b" {
  # Use your own region here but reference to subnet 1b
  availability_zone = "us-west-2b"
}
*/

