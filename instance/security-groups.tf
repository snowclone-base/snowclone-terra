# provision security groups
resource "aws_security_group" "allow_all" {
  name        = "lb_sg"
  description = "testing out ingress and egress in tf "
  vpc_id      = aws_default_vpc.default_vpc.id
  tags = {
    Name = "openBothWays"
  }
}

# Ingress rule
resource "aws_vpc_security_group_ingress_rule" "allow_all" {
  security_group_id = aws_security_group.allow_all.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = -1 #all protocols
}

# Egress rule
resource "aws_vpc_security_group_egress_rule" "allow_all" {
  security_group_id = aws_security_group.allow_all.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = -1 #all protocols
}