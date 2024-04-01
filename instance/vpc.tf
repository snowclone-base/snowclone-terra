# Default VPC
resource "aws_default_vpc" "default_vpc" {}

# route table for private subnet
resource "aws_route_table" "private" {
  vpc_id = aws_default_vpc.default_vpc.id

  route {
    cidr_block = "172.31.0.0/16"
    gateway_id = "local"
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat.id
  }
}

# private subnet a
resource "aws_subnet" "private_subnet_a" {
  cidr_block        = "172.31.253.0/24"
  vpc_id            = aws_default_vpc.default_vpc.id
  availability_zone = "${var.region}a"
}

#private subnet b
resource "aws_subnet" "private_subnet_b" {
  cidr_block        = "172.31.255.0/24"
  vpc_id            = aws_default_vpc.default_vpc.id
  availability_zone = "${var.region}b"
}

#associate private subnets with private route table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.private_subnet_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.private_subnet_b.id
  route_table_id = aws_route_table.private.id
}

# create elastic ip to be used by NAT
resource "aws_eip" "nat" {
  domain = "vpc"
}

#create NAT gateway
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_default_subnet.default_subnet_a.id
}


# default public subnets
resource "aws_default_subnet" "default_subnet_a" {
  availability_zone = "${var.region}a"
}

resource "aws_default_subnet" "default_subnet_b" {
  availability_zone = "${var.region}b"
}
