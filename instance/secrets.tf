variable "my_secret_val" {
  type        = string
  description = "The secret value to be stored in AWS Secrets Manager"
}

resource "aws_secretsmanager_secret" "example" {
  name = "my-secret-name"
}

resource "aws_secretsmanager_secret_version" "example" {
  secret_id     = aws_secretsmanager_secret.example.id
  secret_string = var.my_secret_val
}

# Retrieve the secret value from AWS Secrets Manager
data "aws_secretsmanager_secret_version" "retrieved_secret" {
  secret_id = aws_secretsmanager_secret.example.id
  # Replace this with the ARN or name of your secret in AWS Secrets Manager
}