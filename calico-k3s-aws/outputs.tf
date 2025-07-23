output "instance_1_public_ip" {
  description = "Public IP address of the control plane node"
  value       = aws_instance.k3s_demo_cp.public_ip
}

output "instance_1_private_ip" {
  description = "Private IP address of the control plane node"
  value       = aws_instance.k3s_demo_cp.private_ip
}

output "workers_ip" {
  description = "Public and private IP addresses of worker nodes"
  value = tomap({
    "public_ip"  = aws_instance.k3s_demo_worker_.*.public_ip,
    "private_ip" = aws_instance.k3s_demo_worker_.*.private_ip
  })
}

output "demo_connection" {
  description = "Command to connect to the control plane node"
  value       = "ssh -i ${local_file.k3s_demo_private_key.filename} ubuntu@${aws_instance.k3s_demo_cp.public_ip}"
  sensitive   = false
}

output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.k3s_demo_vpc.id
}

output "subnet_ids" {
  description = "IDs of the created subnets"
  value = {
    subnet_1 = aws_subnet.k3s_demo_subnet_1.id
    subnet_2 = aws_subnet.k3s_demo_subnet_2.id
  }
}

output "security_group_id" {
  description = "ID of the created security group"
  value       = aws_security_group.k3s_demo_SG.id
}
