data "aws_iam_role" "ecsTaskExecutionRole" {
  name = "ecsTaskExecutionRole"
}

resource "aws_iam_role_policy" "secret_access_policy" {
  name = "${var.project_name}_SecretAccessPolicy"
  role = data.aws_iam_role.ecsTaskExecutionRole.name

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
