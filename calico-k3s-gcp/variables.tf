variable "image_id" {
  type        = string
  description = "The image name in gcloud."
  default     = "ubuntu-os-cloud/ubuntu-minimal-2204-jammy-v20231003"

}

variable "cp_instance_type" {
  type    = string
  default = "n1-standard-4"
}

variable "worker_instance_type" {
  type    = string
  default = "n1-standard-2"
}

variable "worker_public_ip" {
  type    = bool
  default = true
}

variable "availability_zone_names" {
  type    = list(string)
  default = ["us-central1-a", "us-central1-b", "us-central1-c"]
}

variable "region" {
  type    = string
  default = "us-cetnral1"
}

variable "project" {
  type    = string
  default = "default"
}

variable "pod_cidr_block" {
  type    = string
  default = "172.17.0.0/16"
}

variable "service_cidr_block" {
  type    = string
  default = "172.34.0.0/16"
}

variable "k3s_features" {
  type    = string
  default = "traefik,local-storage,metrics-server,service-lb"
}

variable "cluster_domain" {
  type    = string
  default = "gcp.local"
}

variable "worker_count" {
  default = "2"
}

variable "k3s_version" {
  type    = string
  default = "1.27"
}

variable "files_path" {
  type    = string
  default = "../"
}

variable "cluster_key_name" {
  type    = string
  default = "calico-demo.pem"
}

variable "enable_nested_virtualization" {
  type    = bool
  default = false
}

variable "disk_size" {
  default = "10"
}

variable "disable_cloud_provider" {
  type    = bool
  default = true
}

variable "worker_enable_gpu" {
  description = "Whether to attach a GPU to worker nodes"
  type        = bool
  default     = false
}

variable "worker_gpu_type" {
  description = "GPU type to attach"
  type        = string
  default     = "nvidia-tesla-t4"
}

variable "worker_gpu_count" {
  description = "Number of GPUs to attach"
  type        = number
  default     = 1
}
