resource "aws_secretsmanager_secret" "postgres_username_secret" {
  name = "${var.project_name}_postgres_username"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "postgres_username_secret_version" {
  secret_id     = aws_secretsmanager_secret.postgres_username_secret.id
  secret_string = var.postgres_username
}

data "aws_secretsmanager_secret_version" "postgres_username_data" {
  secret_id = aws_secretsmanager_secret.postgres_username_secret.id

  depends_on = [aws_secretsmanager_secret_version.postgres_username_secret_version]
}

resource "aws_secretsmanager_secret" "postgres_password_secret" {
  name = "${var.project_name}_postgres_password"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "postgres_password_secret_version" {
  secret_id     = aws_secretsmanager_secret.postgres_password_secret.id
  secret_string = var.postgres_password
}

data "aws_secretsmanager_secret_version" "postgres_password_data" {
  secret_id = aws_secretsmanager_secret.postgres_password_secret.id

  depends_on = [aws_secretsmanager_secret_version.postgres_password_secret_version]
}

resource "aws_secretsmanager_secret" "api_token_secret" {
  name = "${var.project_name}_api_token"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "api_token_secret_version" {
  secret_id     = aws_secretsmanager_secret.api_token_secret.id
  secret_string = var.api_token
}

data "aws_secretsmanager_secret_version" "api_token_data" {
  secret_id = aws_secretsmanager_secret.api_token_secret.id

  depends_on = [aws_secretsmanager_secret_version.api_token_secret_version]
}

resource "aws_secretsmanager_secret" "jwt_secret_secret" {
  name = "${var.project_name}_jwt_secret"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "jwt_secret_secret_version" {
  secret_id     = aws_secretsmanager_secret.jwt_secret_secret.id
  secret_string = var.jwt_secret
}

data "aws_secretsmanager_secret_version" "jwt_secret_data" {
  secret_id = aws_secretsmanager_secret.jwt_secret_secret.id

  depends_on = [aws_secretsmanager_secret_version.jwt_secret_secret_version]
}
