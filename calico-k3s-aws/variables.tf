variable "image_id" {
  type        = string
  description = "The id of the machine image (AMI) to use for the server."
  default     = "ami-03e3c5e419088e824"

  validation {
    # regex(...) fails if it cannot find a match
    condition     = can(regex("^ami-", var.image_id))
    error_message = "The image_id value must be a valid AMI id, starting with \"ami-\"."
  }
}

variable "cp_instance_type" {
  type    = string
  default = "t3.small"
}

variable "worker_instance_type" {
  type    = string
  default = "t3.small"
}

variable "worker_public_ip" {
  type    = bool
  default = true
}

variable "availability_zone_names" {
  type    = list(string)
  default = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "profile" {
  type    = string
  default = "default"
}

variable "credential_file" {
  type    = string
  default = "~/.aws/credentials"
}

variable "cidr_block" {
  type    = string
  default = "172.16.0.0/16"
}

variable "pod_cidr_block" {
  type    = string
  default = "172.32.0.0/16"
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
  default = "aws.local"
}

variable "worker_count" {
  type        = number
  description = "Number of worker nodes in your cluster."
  default     = 1
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

variable "disable_cloud_provider" {
  type    = bool
  default = true
}

variable "enable_nested_virtualization" {
  type        = bool
  description = "Whether to enable nested virtualization (not supported on AWS)"
  default     = false
}

variable "disk_size" {
  type        = number
  description = "Size of the EBS volume in GB."
  default     = 50
}

variable "worker_enable_gpu" {
  description = "Whether to attach a GPU to worker nodes"
  type        = bool
  default     = false
}

variable "worker_gpu_type" {
  description = "GPU type to attach (AWS GPU instance type)"
  type        = string
  default     = "g4dn.xlarge"
}

variable "worker_gpu_count" {
  description = "Number of GPUs to attach"
  type        = number
  default     = 1
}
