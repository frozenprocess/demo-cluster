output "instance_1_public_ip" {
  value = google_compute_instance.k3s_demo_cp.network_interface.0.access_config.0.nat_ip
}

output "instance_1_private_ip" {
  value = google_compute_instance.k3s_demo_cp.network_interface.0.network_ip
}

output "workers_ip" {
  value = tomap({ "public_ip" = google_compute_instance.k3s_demo_worker_.*.network_interface.0.access_config.0.nat_ip,
    "private_ip" = google_compute_instance.k3s_demo_worker_.*.network_interface.0.network_ip }
  )
}

output "demo_connection" {
  description = "Command to connect"
  value       = "ssh -i ${local_file.k3s_demo_private_key.filename} ubuntu@${google_compute_instance.k3s_demo_cp.network_interface.0.access_config.0.nat_ip}"
  sensitive   = false
}
