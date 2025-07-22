provider "google" {
  project = var.project
  region  = var.region
}

data "google_project" "project" {
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
  name        = "demo-permits-${random_string.rand_chars.result}"
  network     = google_compute_network.vpc_network.self_link
  description = "Creates firewall rule targeting tagged instances"

  allow {
    protocol = "tcp"
    ports    = ["22", "6443"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "rules" {
  name        = "vpc-vms-${random_string.rand_chars.result}"
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

resource "google_tags_tag_key" "tag_key" {
    parent = "projects/${data.google_project.project.number}"
    short_name = "cali-demo-tag-${random_string.rand_chars.result}"
    description = "Calico demo Tag Key."
}

resource "google_tags_tag_value" "tag_value" {
    parent = "tagKeys/${google_tags_tag_key.tag_key.name}"
    short_name = "cali-demo-val-${random_string.rand_chars.result}"
    description = "Calico demo Tag value."
}

resource "google_service_account" "default" {
  account_id   = "kube-provider-${random_string.rand_chars.result}"
  display_name = "Custom SA for VM Instance"
}

resource "google_project_iam_custom_role" "sa-role" {
  role_id     = "CalicoK3sDemo${random_string.rand_chars.result}"
  title       = "Calico K3s Demo role for ${random_string.rand_chars.result}"
  description = "Calico K3s Demo role that are required for cloud-provider integration."
  permissions = ["compute.instances.get", "compute.addresses.create", "compute.addresses.delete", "compute.addresses.get", "compute.addresses.list", "compute.addresses.use", "compute.firewalls.create", "compute.firewalls.delete", "compute.firewalls.get", "compute.forwardingRules.create", "compute.forwardingRules.delete", "compute.forwardingRules.get", "compute.httpHealthChecks.create", "compute.httpHealthChecks.delete", "compute.httpHealthChecks.get", "compute.httpHealthChecks.useReadOnly", "compute.instances.list", "compute.instances.use", "compute.networks.updatePolicy", "compute.targetPools.create", "compute.targetPools.delete", "compute.targetPools.get", "compute.targetPools.use"]
}

resource "google_project_iam_member" "sa-role-bind" {
  project = "${var.project}"
  role    = "projects/${var.project}/roles/${google_project_iam_custom_role.sa-role.role_id}"
  member  = "serviceAccount:${google_service_account.default.email}"
}


### GCP INSTANCE CP
resource "google_compute_instance" "k3s_demo_cp" {
  name         = "k3s-demo-cp-${random_string.rand_chars.result}"
  machine_type = var.cp_instance_type
  zone         = "us-central1-a"

  tags = ["k3s-demo-cp"]

  boot_disk {
    initialize_params {
      image = var.image_id
      size  = var.disk_size
    }
  }

  params {
      resource_manager_tags = {
        "tagKeys/${google_tags_tag_key.tag_key.name}" = "tagValues/${google_tags_tag_value.tag_value.name}"
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

  advanced_machine_features {
    enable_nested_virtualization = "${var.enable_nested_virtualization}"
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

  provisioner "file" {
    content = "[Global]\nproject-id=${var.project}\nnetwork-name=${google_compute_network.vpc_network.name}\nnode-tags=${element(tolist(self.tags), 1)}"
    destination = "/tmp/cloud.config"
  }

  provisioner "file" {
    source      = "${var.files_path}gcp/gcp-controller.yaml"
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

  service_account {
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    email  = google_service_account.default.email
    scopes = ["cloud-platform"]
  }

}
### GCP INSTANCE CP

### GCP WORKERS
resource "google_compute_instance" "k3s_demo_worker_" {
  count        = var.worker_count
  name         = "k3s-demo-worker-${random_string.rand_chars.result}-${count.index}"
  machine_type = var.worker_instance_type
  zone         = "us-central1-a"

  tags = ["k3s-demo-workers"]

  boot_disk {
    initialize_params {
      image = var.image_id
      size  = var.disk_size
    }
  }

  params {
      resource_manager_tags = {
        "tagKeys/${google_tags_tag_key.tag_key.name}" = "tagValues/${google_tags_tag_value.tag_value.name}"
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

  dynamic "guest_accelerator" {
    for_each = var.worker_enable_gpu ? [1] : []
    content {
      type  = var.worker_gpu_type
      count = var.worker_gpu_count
    }
  }

  dynamic "scheduling" {
    for_each = var.worker_enable_gpu ? [1] : []
    content {
      on_host_maintenance = "TERMINATE"
    }
  }

  advanced_machine_features {
    enable_nested_virtualization = "${var.enable_nested_virtualization}"
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

  service_account {
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    email  = google_service_account.default.email
    scopes = ["cloud-platform"]
  }

}
### GCP WORKERS

