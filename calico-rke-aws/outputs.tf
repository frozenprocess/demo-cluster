output "instance_1_public_ip" {
  value = aws_instance.rancher_demo_instance_1.public_ip
}

output "instance_2_public_ip" {
  value = aws_instance.rancher_demo_instance_2.public_ip
}

output "instance_1_private_ip" {
  value = aws_instance.rancher_demo_instance_1.private_ip
}

output "instance_2_private_ip" {
  value = aws_instance.rancher_demo_instance_2.private_ip
}
