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
          aws_secretsmanager_secret_version.postgres_username_secret_version.arn,
          aws_secretsmanager_secret_version.postgres_password_secret_version.arn,
          aws_secretsmanager_secret_version.api_token_secret_version.arn,
          aws_secretsmanager_secret_version.jwt_secret_secret_version.arn
        ]
      }
    ]
  })
}
