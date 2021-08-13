variable "image_id" {
  type        = string
  description = "The id of the machine image (AMI) to use for the server."
  default = "ami-03e3c5e419088e824"

  validation {
    # regex(...) fails if it cannot find a match
    condition     = can(regex("^ami-", var.image_id))
    error_message = "The image_id value must be a valid AMI id, starting with \"ami-\"."
  }
}

variable "instance_type" {
    type = string
    default = "t3.small"
}

variable "availability_zone_names" {
  type    = list(string)
  default = ["us-west-2a","us-west-2b","us-west-2c"]
}

variable "region" {
  type=string
  default = "us-west-2"
}

variable "profile" {
    type=string
    default = "default"
}

variable "credential_file" {
  type=string
  default="~/.aws/credentials"
}

variable "cidr_block" {
    type=string
    default="172.16.0.0/16"
}

provider "aws" {
  region                  = var.region
  shared_credentials_file = var.credential_file
  profile                 = var.profile
}

resource "aws_vpc" "k3s_demo_vpc" {
  cidr_block = var.cidr_block
  tags = {
    Environment = "Calico Demo"
    Name        = "Calico Demo VPC"
  }
}

resource "aws_internet_gateway" "k3s_demo_igw" {
  vpc_id = aws_vpc.k3s_demo_vpc.id

  tags = {
    Environment = "Calico Demo"
    Name        = "Calico Demo igw"
  }
}

resource "aws_subnet" "k3s_demo_subnet_1" {
  vpc_id     = aws_vpc.k3s_demo_vpc.id
  cidr_block = cidrsubnet(aws_vpc.k3s_demo_vpc.cidr_block, 8, 1)
  availability_zone = var.availability_zone_names[0]
  tags = {
    Environment = "Calico Demo"
    Name        = "Calico Demo Subnet 1"
  }
}

resource "aws_subnet" "k3s_demo_subnet_2" {
  vpc_id     = aws_vpc.k3s_demo_vpc.id
  cidr_block = cidrsubnet(aws_vpc.k3s_demo_vpc.cidr_block, 8, 2)
  availability_zone = length(var.availability_zone_names) > 1 ? var.availability_zone_names[1] : var.availability_zone_names[0]
  tags = {
    Environment = "Calico Demo"
    Name        = "Calico Demo Subnet 2"
  }
}

resource "aws_route_table" "k3s_demo_routes" {
  vpc_id = aws_vpc.k3s_demo_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k3s_demo_igw.id
  }
  tags = {
    Environment = "Calico Demo"
    Name        = "Calico Demo Route"
  }
}

resource "aws_route_table_association" "k3s_demo_route_associate1" {
  subnet_id      = aws_subnet.k3s_demo_subnet_1.id
  route_table_id = aws_route_table.k3s_demo_routes.id
}

resource "aws_route_table_association" "k3s_demo_route_associate2" {
  subnet_id      = aws_subnet.k3s_demo_subnet_2.id
  route_table_id = aws_route_table.k3s_demo_routes.id
}

resource "aws_security_group" "k3s_demo_SG" {
  name   = "Calico Demo SG"
  vpc_id = aws_vpc.k3s_demo_vpc.id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

#  ingress {
#    description = "Allow connection to K3s apiserver."
#    from_port = 6443
#    to_port   = 6443
#    protocol  = "tcp"
#    cidr_blocks = ["0.0.0.0/0"]
#  }

  ingress {
    description = "Allow Internal network to communicate"
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = [aws_vpc.k3s_demo_vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Environment = "Calico Demo"
    Name        = "Calico Demo SG"
  }

}

resource "tls_private_key" "k3s_demo_key" {
  algorithm = "RSA"
  rsa_bits  = "1024"
}

resource "local_file" "k3s_demo_private_key" {
  content         = tls_private_key.k3s_demo_key.private_key_pem
  filename        = "calico-demo.pem"
  file_permission = "0600"
}

resource "aws_key_pair" "k3s_demo_ssh_key" {
  key_name   = "k3s_demo_ssh_key"
  public_key = tls_private_key.k3s_demo_key.public_key_openssh
}

resource "aws_instance" "k3s_demo_instance_1" {
  ami               = var.image_id
  instance_type     = var.instance_type
  key_name          = "k3s_demo_ssh_key"
  availability_zone = aws_subnet.k3s_demo_subnet_1.availability_zone
  subnet_id         = aws_subnet.k3s_demo_subnet_1.id

  vpc_security_group_ids = [aws_security_group.k3s_demo_SG.id]
  monitoring             = false

  associate_public_ip_address = true
  credit_specification {
    cpu_credits = "unlimited"
  }
  disable_api_termination = false
  ebs_optimized           = false
  tags = {
    Environment = "Calico Demo"
    Name        = "K3s Demo Instance 1"
  }
}

resource "aws_instance" "k3s_demo_instance_2" {
  ami               = var.image_id
  instance_type     = var.instance_type
  key_name          = "k3s_demo_ssh_key"
  availability_zone = aws_subnet.k3s_demo_subnet_2.availability_zone
  subnet_id         = aws_subnet.k3s_demo_subnet_2.id

  vpc_security_group_ids = [aws_security_group.k3s_demo_SG.id]
  monitoring             = false

  associate_public_ip_address = true
  credit_specification {
    cpu_credits = "unlimited"
  }
  disable_api_termination = false
  ebs_optimized           = false
  tags = {
    Environment = "Calico Demo"
    Name        = "K3s Demo Instance 2"
  }
}
