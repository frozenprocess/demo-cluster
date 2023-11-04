output "instance_1_public_ip" {
  value = aws_instance.k3s_demo_cp.public_ip
}

output "instance_1_private_ip" {
  value = aws_instance.k3s_demo_cp.private_ip
}

output "workers_ip" {
  value = tomap({ "public_ip" = aws_instance.k3s_demo_worker_.*.public_ip,
    "private_ip" = aws_instance.k3s_demo_worker_.*.private_ip }
  )
}

output "demo_connection" {
  description = "Command to connect"
  value       = "ssh -i ${local_file.k3s_demo_private_key.filename} ubuntu@${aws_instance.k3s_demo_cp.public_ip}"
  sensitive   = false
}
