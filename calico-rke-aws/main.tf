provider "aws" {
  region                  = var.region
  shared_credentials_file = var.credential_file
  profile                 = var.profile
}

resource "aws_vpc" "rancher_demo_vpc" {
  cidr_block = var.cidr_block
  tags = {
    Environment = "Calico rancher demo"
    Name        = "Calico rancher demo VPC"
  }
}

resource "aws_internet_gateway" "rancher_demo_igw" {
  vpc_id = aws_vpc.rancher_demo_vpc.id

  tags = {
    Environment = "Calico rancher demo"
    Name        = "Calico rancher demo igw"
  }
}

resource "aws_subnet" "rancher_demo_subnet_1" {
  vpc_id     = aws_vpc.rancher_demo_vpc.id
  cidr_block = cidrsubnet(aws_vpc.rancher_demo_vpc.cidr_block, 8, 1)
  availability_zone = var.availability_zone_names[0]
  tags = {
    Environment = "Calico rancher demo"
    Name        = "Calico rancher demo Subnet 1"
  }
}

resource "aws_subnet" "rancher_demo_subnet_2" {
  vpc_id     = aws_vpc.rancher_demo_vpc.id
  cidr_block = cidrsubnet(aws_vpc.rancher_demo_vpc.cidr_block, 8, 2)
  availability_zone = length(var.availability_zone_names) > 1 ? var.availability_zone_names[1] : var.availability_zone_names[0]
  tags = {
    Environment = "Calico rancher demo"
    Name        = "Calico rancher demo Subnet 2"
  }
}

resource "aws_route_table" "rancher_demo_routes" {
  vpc_id = aws_vpc.rancher_demo_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.rancher_demo_igw.id
  }
  tags = {
    Environment = "Calico rancher demo"
    Name        = "Calico rancher demo Route"
  }
}

resource "aws_route_table_association" "rancher_demo_route_associate1" {
  subnet_id      = aws_subnet.rancher_demo_subnet_1.id
  route_table_id = aws_route_table.rancher_demo_routes.id
}

resource "aws_route_table_association" "rancher_demo_route_associate2" {
  subnet_id      = aws_subnet.rancher_demo_subnet_2.id
  route_table_id = aws_route_table.rancher_demo_routes.id
}

resource "aws_security_group" "rancher_demo_SG" {
  name   = "Calico rancher demo SG"
  vpc_id = aws_vpc.rancher_demo_vpc.id

  ingress {
    description = "Allow SSH from remote sources."
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow remote connection to apiserver."
    from_port = 6443
    to_port   = 6443
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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
    Environment = "Calico rancher demo"
    Name        = "Calico rancher demo SG"
  }

}

resource "tls_private_key" "rancher_demo_key" {
  algorithm = "RSA"
  rsa_bits  = "1024"
}

resource "local_file" "rancher_demo_private_key" {
  content         = tls_private_key.rancher_demo_key.private_key_pem
  filename        = "calico-demo.pem"
  file_permission = "0600"
}

resource "aws_key_pair" "rancher_demo_ssh_key" {
  key_name   = "rancher_demo_ssh_key"
  public_key = tls_private_key.rancher_demo_key.public_key_openssh
}

resource "aws_instance" "rancher_demo_instance_1" {
  ami               = var.image_id
  instance_type     = var.instance_type
  key_name          = "rancher_demo_ssh_key"
  availability_zone = aws_subnet.rancher_demo_subnet_1.availability_zone
  subnet_id         = aws_subnet.rancher_demo_subnet_1.id

  vpc_security_group_ids = [aws_security_group.rancher_demo_SG.id]
  monitoring             = false

  associate_public_ip_address = true

  provisioner "file" {
    source      = "files/docker-install.sh"
    destination = "/tmp/docker-install.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/docker-install.sh",
      "/tmp/docker-install.sh"
    ]
  }

  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ubuntu"
    private_key = tls_private_key.rancher_demo_key.private_key_pem
  }

  credit_specification {
    cpu_credits = "unlimited"
  }
  disable_api_termination = false
  ebs_optimized           = false
  tags = {
    Environment = "Calico rancher demo"
    Name        = "rancher Demo Instance 1"
  }
}

resource "aws_instance" "rancher_demo_instance_2" {
  ami               = var.image_id
  instance_type     = var.instance_type
  key_name          = "rancher_demo_ssh_key"
  availability_zone = aws_subnet.rancher_demo_subnet_2.availability_zone
  subnet_id         = aws_subnet.rancher_demo_subnet_2.id

  vpc_security_group_ids = [aws_security_group.rancher_demo_SG.id]
  monitoring             = false

  associate_public_ip_address = true

  provisioner "file" {
    source      = "files/docker-install.sh"
    destination = "/tmp/docker-install.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/docker-install.sh",
      "/tmp/docker-install.sh"
    ]
  }

  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ubuntu"
    private_key = tls_private_key.rancher_demo_key.private_key_pem
  }

  credit_specification {
    cpu_credits = "unlimited"
  }
  disable_api_termination = false
  ebs_optimized           = false
  tags = {
    Environment = "Calico rancher demo"
    Name        = "rancher Demo Instance 2"
  }
}
