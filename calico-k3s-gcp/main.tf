provider "google" {
  project = var.project
  region  = var.region
}

resource "random_string" "rand_chars" {
  length  = 8
  upper   = false
  lower   = true
  numeric = false
  special = false
}


resource "google_compute_network" "vpc_network" {
  name                    = "k3s-demo-${random_string.rand_chars.result}"
  auto_create_subnetworks = "true"
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

resource "google_compute_firewall" "allow-rule" {
  name        = "demo-permits"
  network     = google_compute_network.vpc_network.self_link
  description = "Creates firewall rule targeting tagged instances"

  allow {
    protocol = "tcp"
    ports    = ["22", "6443"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "rules" {
  name        = "vpc-vms"
  network     = google_compute_network.vpc_network.self_link
  description = "Creates firewall rule targeting tagged instances"

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_tags = ["k3s-demo-cp", "k3s-demo-workers"]
}


### GCP INSTANCE CP
resource "google_compute_instance" "k3s_demo_cp" {
  name         = "k3s-demo-cp"
  machine_type = var.cp_instance_type
  zone         = "us-central1-a"

  tags = ["k3s-demo-cp"]

  boot_disk {
    initialize_params {
      image = var.image_id
    }
  }

  metadata = {
    ssh-keys               = "ubuntu:${tls_private_key.k3s_demo_key.public_key_openssh}"
    block-project-ssh-keys = true
  }

  network_interface {
    # A default network is created for all GCP projects
    network = google_compute_network.vpc_network.self_link
    access_config {
    }
  }


  connection {
    type        = "ssh"
    host        = self.network_interface.0.access_config.0.nat_ip
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
      "sudo /tmp/k3s-cp.sh ${var.pod_cidr_block} ${var.service_cidr_block} ${var.cluster_domain} ${var.k3s_features}",
      "chmod +x /tmp/calico-install.sh",
      "sudo /tmp/calico-install.sh ${var.pod_cidr_block}"
    ]
  }


}
### GCP INSTANCE CP

### GCP WORKERS
resource "google_compute_instance" "k3s_demo_worker_" {
  count        = var.worker_count
  name         = "k3s-demo-worker-${count.index}"
  machine_type = var.worker_instance_type
  zone         = "us-central1-a"

  tags = ["k3s-demo-workers"]

  boot_disk {
    initialize_params {
      image = var.image_id
    }
  }

  metadata = {
    ssh-keys               = "ubuntu:${tls_private_key.k3s_demo_key.public_key_openssh}"
    block-project-ssh-keys = true
  }

  network_interface {
    network = google_compute_network.vpc_network.self_link
    access_config {
    }
  }

  connection {
    type        = "ssh"
    host        = self.network_interface.0.access_config.0.nat_ip
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
      "sudo /tmp/k3s-node.sh ${google_compute_instance.k3s_demo_cp.network_interface.0.access_config.0.nat_ip}"
    ]
  }


}
### GCP WORKERS

