output "instance_1_public_ip" {
  value = aws_instance.k3s_demo_cp.public_ip
}

output "instance_1_private_ip" {
  value = aws_instance.k3s_demo_cp.private_ip
}

output "workers_ip" {
  value = zipmap( aws_instance.k3s_demo_worker_.*.public_ip, aws_instance.k3s_demo_worker_.*.private_ip ) 
}
