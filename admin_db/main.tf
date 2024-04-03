resource "aws_dynamodb_table" "db" {
  name         = "backend_info"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"
  attribute {
    name = "id"
    type = "S"
  }

  table_class = "STANDARD_INFREQUENT_ACCESS"
}

output "private_subnet_a_id" {
  value = aws_subnet.private_subnet_a.id
}

output "private_subnet_b_id" {
  value = aws_subnet.private_subnet_b.id
}

terraform {
    backend "s3" {}
}