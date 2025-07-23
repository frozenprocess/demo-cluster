terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~>4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~>2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_subscription" "current" {}

resource "random_string" "rand_chars" {
  length  = 8
  upper   = false
  lower   = true
  numeric = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "k3s-demo-${random_string.rand_chars.result}"
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "k3s-demo-vnet-${random_string.rand_chars.result}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "k3s-demo-subnet-${random_string.rand_chars.result}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "nsg" {
  name                = "k3s-demo-nsg-${random_string.rand_chars.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "KubernetesAPI"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "InternalTraffic"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.0.0.0/16"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "nsg_association" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "tls_private_key" "k3s_demo_key" {
  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "local_file" "k3s_demo_private_key" {
  content         = tls_private_key.k3s_demo_key.private_key_pem
  filename        = var.cluster_key_name
  file_permission = "0600"
}

resource "azurerm_user_assigned_identity" "k3s_identity" {
  name                = "k3s-demo-identity-${random_string.rand_chars.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

resource "azurerm_role_assignment" "vm_contributor" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.k3s_identity.principal_id
}

resource "azurerm_public_ip" "cp_public_ip" {
  name                = "k3s-cp-public-ip-${random_string.rand_chars.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "cp_nic" {
  name                = "k3s-cp-nic-${random_string.rand_chars.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.cp_public_ip.id
  }
}

resource "azurerm_linux_virtual_machine" "k3s_demo_cp" {
  name                = "k3s-demo-cp-${random_string.rand_chars.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.cp_instance_type
  admin_username      = "ubuntu"

  network_interface_ids = [
    azurerm_network_interface.cp_nic.id,
  ]

  admin_ssh_key {
    username   = "ubuntu"
    public_key = tls_private_key.k3s_demo_key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = var.disk_size
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.k3s_identity.id]
  }

  tags = {
    Environment = "k3s-demo"
    Role        = "control-plane"
  }

  connection {
    type        = "ssh"
    host        = azurerm_public_ip.cp_public_ip.ip_address
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

  provisioner "file" {
    content = "[Global]\nresource-group=${azurerm_resource_group.rg.name}\nvnet-name=${azurerm_virtual_network.vnet.name}\nsubnet-name=${azurerm_subnet.subnet.name}\nlocation=${var.location}\nuse-managed-identity-extension=true\nuse-instance-metadata=true"
    destination = "/tmp/cloud.config"
  }

  provisioner "file" {
    source      = "${var.files_path}azure/azure-controller.yaml"
    destination = "/tmp/cloud-controller.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/prepare.sh",
      "sudo /tmp/prepare.sh ${var.k3s_version}",
      "chmod +x /tmp/k3s-cp.sh",
      "sudo /tmp/k3s-cp.sh ${var.pod_cidr_block} ${var.service_cidr_block} ${var.cluster_domain} ${var.k3s_features} ${var.disable_cloud_provider}",
      "chmod +x /tmp/calico-install.sh",
      "sudo /tmp/calico-install.sh ${var.pod_cidr_block}"
    ]
  }
}

resource "azurerm_public_ip" "worker_public_ips" {
  count               = var.worker_count
  name                = "k3s-worker-public-ip-${random_string.rand_chars.result}-${count.index}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "worker_nics" {
  count               = var.worker_count
  name                = "k3s-worker-nic-${random_string.rand_chars.result}-${count.index}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.worker_public_ips[count.index].id
  }
}

resource "azurerm_linux_virtual_machine" "k3s_demo_workers" {
  count               = var.worker_count
  name                = "k3s-demo-worker-${random_string.rand_chars.result}-${count.index}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.worker_instance_type
  admin_username      = "ubuntu"

  network_interface_ids = [
    azurerm_network_interface.worker_nics[count.index].id,
  ]

  admin_ssh_key {
    username   = "ubuntu"
    public_key = tls_private_key.k3s_demo_key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = var.disk_size
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.k3s_identity.id]
  }

  tags = {
    Environment = "k3s-demo"
    Role        = "worker"
  }

  connection {
    type        = "ssh"
    host        = azurerm_public_ip.worker_public_ips[count.index].ip_address
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
      "sudo /tmp/k3s-node.sh ${azurerm_public_ip.cp_public_ip.ip_address}"
    ]
  }
} 