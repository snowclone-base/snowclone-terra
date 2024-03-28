# create RDS
resource "aws_db_instance" "rds-db" {
  allocated_storage      = 10
  apply_immediately      = true
  db_name                = "postgres"
  engine                 = "postgres"
  engine_version         = "14"
  instance_class         = "db.t3.micro"
  parameter_group_name   = aws_db_parameter_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true
  username               = "postgres"
  password               = data.aws_secretsmanager_secret_version.retrieved_secret.secret_string
}

# create parameter group for db
resource "aws_db_parameter_group" "rds" {
  name   = var.project_name
  family = "postgres14"

  parameter {
    name  = "log_connections"
    value = "1"
  }
}

resource "aws_security_group" "rds" {
  name   = "${var.project_name}_rds"
  vpc_id = aws_default_vpc.default_vpc.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}_rds"
  }
}