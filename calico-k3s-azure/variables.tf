variable "location" {
  type        = string
  description = "The Azure region where resources will be created."
  default     = "East US"
}

variable "cp_instance_type" {
  type        = string
  description = "The Azure VM size for the control plane node."
  default     = "Standard_D4s_v3"
}

variable "worker_instance_type" {
  type        = string
  description = "The Azure VM size for worker nodes."
  default     = "Standard_D2s_v3"
}

variable "worker_public_ip" {
  type        = bool
  description = "Whether worker nodes should have public IP addresses."
  default     = true
}

variable "availability_zone_names" {
  type        = list(string)
  description = "List of availability zones to use (Azure supports 1, 2, 3)."
  default     = ["1", "2", "3"]
}

variable "pod_cidr_block" {
  type        = string
  description = "Range of IP that will be used as Kubernetes Pod CIDR."
  default     = "172.17.0.0/16"
}

variable "service_cidr_block" {
  type        = string
  description = "Range of the IPs that will be used for Kubernetes services."
  default     = "172.34.0.0/16"
}

variable "k3s_features" {
  type        = string
  description = "Which k3s features should be enabled."
  default     = "traefik,local-storage,metrics-server,service-lb"
}

variable "cluster_domain" {
  type        = string
  description = "Domain name that will be used for your cluster."
  default     = "azure.local"
}

variable "worker_count" {
  type        = number
  description = "Number of worker nodes in your cluster."
  default     = 2
}

variable "k3s_version" {
  type        = string
  description = "K3s Version that would be installed."
  default     = "1.27"
}

variable "files_path" {
  type        = string
  description = "Path to the files directory."
  default     = "../"
}

variable "cluster_key_name" {
  type        = string
  description = "Cluster Key name."
  default     = "calico-demo.pem"
}

variable "disk_size" {
  type        = number
  description = "Size of the OS disk in GB."
  default     = 10
}

variable "disable_cloud_provider" {
  type        = bool
  description = "Whether to disable cloud provider integration."
  default     = true
}

variable "worker_enable_gpu" {
  type        = bool
  description = "Whether to attach a GPU to worker nodes."
  default     = false
}

variable "worker_gpu_type" {
  type        = string
  description = "GPU type to attach (Azure GPU VM sizes)."
  default     = "Standard_NC4as_T4_v3"
}

variable "worker_gpu_count" {
  type        = number
  description = "Number of GPUs to attach."
  default     = 1
} 