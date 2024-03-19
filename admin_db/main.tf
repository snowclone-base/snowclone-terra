terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_s3_bucket" "s3" {
  bucket = "backends-state"
}

resource "aws_instance" "admin" {
  ami               = data.aws_ami.ubuntu.id
  instance_type     = "t2.micro"
  availability_zone = "us-east-1a"

  tags = {
    Name = "admin"
  }
}

resource "aws_ebs_volume" "admin-db" {
  availability_zone = "us-east-1a"
  size              = 10
}

resource "aws_volume_attachment" "admin-db-attachment" {
  device_name = "/dev/xvdf"
  instance_id = aws_instance.admin.id
  volume_id   = aws_ebs_volume.admin-db.id
}
