# provision security group for load balancer
resource "aws_security_group" "alb_web_traffic" {
  name        = "${var.project_name}_lb_sg"
  description = "only allow http and https inbound. allow all outbound"
  vpc_id      = aws_default_vpc.default_vpc.id
  tags = {
    Name = "${var.project_name}_internet_facing_alb"
  }
}

# lb Ingress rules
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.alb_web_traffic.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  ip_protocol = "tcp"
  to_port     = 80
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.alb_web_traffic.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  ip_protocol = "tcp"
  to_port     = 443
}

# lb Egress rules
resource "aws_vpc_security_group_egress_rule" "allow_all" {
  security_group_id = aws_security_group.alb_web_traffic.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = -1 #all protocols
}

# API servers security group
resource "aws_security_group" "api_servers" {
  name        = "${var.project_name}_api_sg"
  description = "only reachable from lb and db. NAT allows image pulls"
  vpc_id      = aws_default_vpc.default_vpc.id
  tags = {
    Name = "${var.project_name}_api_sg"
  }
}

# API ingress rule from alb
resource "aws_vpc_security_group_ingress_rule" "alb-to-api" {
  security_group_id = aws_security_group.api_servers.id

  ip_protocol                  = -1
  referenced_security_group_id = aws_security_group.alb_web_traffic.id
}

# API ingress rule from db
resource "aws_vpc_security_group_ingress_rule" "db-to-api" {
  security_group_id = aws_security_group.api_servers.id

  from_port                    = 5432
  ip_protocol                  = "tcp"
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.rds.id
}

# API egress rule. Wide open to allow for image pulls. 
resource "aws_vpc_security_group_egress_rule" "allow-all" {
  security_group_id = aws_security_group.api_servers.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = -1
}

# DB security group
resource "aws_security_group" "rds" {
  name        = "${var.project_name}_rds"
  vpc_id      = aws_default_vpc.default_vpc.id
  description = "only reachable from api servers"
  tags = {
    Name = "${var.project_name}_rds"
  }
}

# DB ingress rule from API
resource "aws_vpc_security_group_ingress_rule" "allow-api-to-db" {
  security_group_id = aws_security_group.rds.id

  from_port                    = 5432
  ip_protocol                  = "tcp"
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.api_servers.id
}

# DB egress rule to API
resource "aws_vpc_security_group_egress_rule" "allow-db-to-api" {
  security_group_id = aws_security_group.rds.id

  from_port                    = 5432
  ip_protocol                  = "tcp"
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.api_servers.id
}
