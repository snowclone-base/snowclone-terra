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
        { name = "PG_PASSWORD", value = "${data.aws_secretsmanager_secret_version.retrieved_secret.secret_string}" },
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
        { name = "DATABASE_URL", value = "postgresql://postgres:${data.aws_secretsmanager_secret_version.retrieved_secret.secret_string}@${aws_db_instance.rds-db.endpoint}/postgres" },
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