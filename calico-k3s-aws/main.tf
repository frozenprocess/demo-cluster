provider "aws" {
  region                   = var.region
  shared_credentials_files = [var.credential_file]
  profile                  = var.profile
}

resource "random_string" "rand_chars" {
  length  = 8
  upper   = false
  lower   = true
  numeric = false
  special = false
}

resource "aws_vpc" "k3s_demo_vpc" {
  cidr_block                       = var.cidr_block
  assign_generated_ipv6_cidr_block = true
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

  ipv6_cidr_block                                = cidrsubnet(aws_vpc.k3s_demo_vpc.ipv6_cidr_block, 8, 1)
  map_public_ip_on_launch                        = false
  enable_resource_name_dns_aaaa_record_on_launch = true
  assign_ipv6_address_on_creation                = true


  availability_zone = var.availability_zone_names[0]
  tags = {
    Environment = "Calico Demo"
    Name        = "Calico Demo Subnet 1"
  }
}

resource "aws_subnet" "k3s_demo_subnet_2" {
  vpc_id     = aws_vpc.k3s_demo_vpc.id
  cidr_block = cidrsubnet(aws_vpc.k3s_demo_vpc.cidr_block, 8, 2)

  ipv6_cidr_block                                = cidrsubnet(aws_vpc.k3s_demo_vpc.ipv6_cidr_block, 8, 2)
  map_public_ip_on_launch                        = false
  enable_resource_name_dns_aaaa_record_on_launch = true
  assign_ipv6_address_on_creation                = true

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
  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.k3s_demo_igw.id
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
    description = "Allow SSH from remote sources."
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description      = "Allow SSH from remote sources."
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description = "Allow remote connection to apiserver."
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description      = "Allow remote connection to apiserver."
    from_port        = 6443
    to_port          = 6443
    protocol         = "tcp"
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description = "Allow Internal network to communicate"
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = [aws_vpc.k3s_demo_vpc.cidr_block]
  }

  ingress {
    description      = "Allow Internal network to communicate"
    from_port        = 0
    to_port          = 0
    protocol         = -1
    ipv6_cidr_blocks = [aws_vpc.k3s_demo_vpc.ipv6_cidr_block]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port        = 0
    to_port          = 0
    protocol         = -1
    ipv6_cidr_blocks = ["::/0"]
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
  filename        = var.cluster_key_name
  file_permission = "0600"
}

resource "aws_key_pair" "k3s_demo_ssh_key" {
  key_name   = "k3s_demo_ssh_key_${random_string.rand_chars.result}"
  public_key = tls_private_key.k3s_demo_key.public_key_openssh
}

resource "aws_instance" "k3s_demo_cp" {
  ami                = var.image_id
  instance_type      = var.cp_instance_type
  key_name           = aws_key_pair.k3s_demo_ssh_key.key_name
  availability_zone  = aws_subnet.k3s_demo_subnet_1.availability_zone
  subnet_id          = aws_subnet.k3s_demo_subnet_1.id
  ipv6_address_count = 1

  vpc_security_group_ids = [aws_security_group.k3s_demo_SG.id]
  monitoring             = false

  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ubuntu"
    private_key = tls_private_key.k3s_demo_key.private_key_pem
  }

  provisioner "file" {
    source      = "${var.files_path}prepare.sh"
    destination = "/tmp/prepare.sh"
  }


  provisioner "file" {
    source      = "${var.files_path}k3s-cp.sh"
    destination = "/tmp/k3s-cp.sh"
  }

  provisioner "file" {
    source      = "${var.files_path}calico-install.sh"
    destination = "/tmp/calico-install.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/prepare.sh",
      "sudo /tmp/prepare.sh ${var.k3s_version}",
      "chmod +x /tmp/k3s-cp.sh",
      "sudo /tmp/k3s-cp.sh ${var.pod_cidr_block} ${var.service_cidr_block} ${var.cluster_domain} ${var.k3s_features} ${self.ipv6_addresses[0]}"
    ]
  }

  associate_public_ip_address = true
  credit_specification {
    cpu_credits = "unlimited"
  }
  disable_api_termination = false
  ebs_optimized           = false
  tags = {
    Environment = "Calico Demo"
    Name        = "K3s Demo Instance cp 1"
  }
}

resource "aws_instance" "k3s_demo_worker_" {
  count             = var.worker_count
  ami               = var.image_id
  instance_type     = var.worker_instance_type
  key_name          = aws_key_pair.k3s_demo_ssh_key.key_name
  availability_zone = aws_subnet.k3s_demo_subnet_2.availability_zone
  subnet_id         = aws_subnet.k3s_demo_subnet_2.id

  vpc_security_group_ids = [aws_security_group.k3s_demo_SG.id]
  monitoring             = false

  associate_public_ip_address = var.worker_public_ip ? true : false
  credit_specification {
    cpu_credits = "unlimited"
  }

  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ubuntu"
    private_key = tls_private_key.k3s_demo_key.private_key_pem
  }

  provisioner "file" {
    source      = "${var.files_path}prepare.sh"
    destination = "/tmp/prepare.sh"
  }

  provisioner "file" {
    source      = "${var.files_path}k3s-node.sh"
    destination = "/tmp/k3s-node.sh"
  }

  provisioner "file" {
    source      = var.cluster_key_name
    destination = "/home/ubuntu/calico-demo.pem"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/prepare.sh",
      "sudo /tmp/prepare.sh ${var.k3s_version}",
      "chmod +x /tmp/k3s-node.sh",
      "sudo /tmp/k3s-node.sh ${aws_instance.k3s_demo_cp.private_ip} ${self.ipv6_addresses[0]}"
    ]
  }

  disable_api_termination = false
  ebs_optimized           = false
  tags = {
    Environment = "Calico Demo"
    Name        = "K3s Demo Instance ${count.index}"
  }
}
