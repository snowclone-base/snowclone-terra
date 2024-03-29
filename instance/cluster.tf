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