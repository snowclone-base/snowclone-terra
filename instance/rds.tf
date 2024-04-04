# create RDS
resource "aws_db_instance" "rds-db" {
  allocated_storage      = 10
  apply_immediately      = true
  db_name                = "${var.project_name}_pg_db"
  engine                 = "postgres"
  engine_version         = "14"
  instance_class         = "db.t3.micro"
  parameter_group_name   = aws_db_parameter_group.rds.name
  db_subnet_group_name   = aws_db_subnet_group.rds-postgres.id
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true
  username               = aws_secretsmanager_secret_version.postgres_username_secret_version.secret_string
  password               = aws_secretsmanager_secret_version.postgres_password_secret_version.secret_string

}

# create parameter group for db
resource "aws_db_parameter_group" "rds" {
  name   = "${var.project_name}-db-param-group"
  family = "postgres14"

  parameter {
    name  = "log_connections"
    value = "1"
  }
}

resource "aws_db_subnet_group" "rds-postgres" {
  name       = "${var.project_name}_rds_subnet_group"
  subnet_ids = [data.aws_subnet.private_subnet_a.id, data.aws_subnet.private_subnet_b.id]

  tags = {
    Name = "${var.project_name}_rds"
  }
}
