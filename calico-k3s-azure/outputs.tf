output "instance_1_public_ip" {
  description = "Public IP address of the control plane node"
  value       = azurerm_public_ip.cp_public_ip.ip_address
}

output "instance_1_private_ip" {
  description = "Private IP address of the control plane node"
  value       = azurerm_network_interface.cp_nic.private_ip_address
}

output "workers_ip" {
  description = "Public and private IP addresses of worker nodes"
  value = tomap({
    "public_ip"  = azurerm_public_ip.worker_public_ips[*].ip_address,
    "private_ip" = azurerm_network_interface.worker_nics[*].private_ip_address
  })
}

output "demo_connection" {
  description = "Command to connect to the control plane node"
  value       = "ssh -i ${local_file.k3s_demo_private_key.filename} ubuntu@${azurerm_public_ip.cp_public_ip.ip_address}"
  sensitive   = false
}

output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.rg.name
}

output "virtual_network_name" {
  description = "Name of the created virtual network"
  value       = azurerm_virtual_network.vnet.name
}

output "subnet_name" {
  description = "Name of the created subnet"
  value       = azurerm_subnet.subnet.name
} 