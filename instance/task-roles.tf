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

resource "aws_iam_role_policy" "secret_access_policy" {
  name = "SecretAccessPolicy"
  role = aws_iam_role.ecsTaskExecutionRole.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "SecretAccess",
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DeleteSecret" // Added deletion permission
        ]
        Resource = [
          data.aws_secretsmanager_secret_version.postgres_username_data.arn,
          data.aws_secretsmanager_secret_version.postgres_password_data.arn,
          data.aws_secretsmanager_secret_version.api_token_data.arn,
          data.aws_secretsmanager_secret_version.jwt_secret_data.arn
        ]
      }
    ]
  })
}
