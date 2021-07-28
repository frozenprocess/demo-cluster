variable "image_id" {
  type        = string
  description = "The id of the machine image (AMI) to use for the server."
  default = "ami-03e3c5e419088e824"

  validation {
    # regex(...) fails if it cannot find a match
    condition     = can(regex("^ami-", var.image_id))
    error_message = "The image_id value must be a valid AMI id, starting with \"ami-\"."
  }
}

variable "instance_type" {
    type = string
    default = "t3.small"
}

variable "availability_zone_names" {
  type    = list(string)
  default = ["us-west-2a","us-west-2b","us-west-2c"]
}

variable "region" {
  type=string
  default = "us-west-2"
}

variable "profile" {
    type=string
    default = "default"
}

variable "credential_file" {
  type=string
  default="~/.aws/credentials"
}

variable "cidr_block" {
    type=string
    default="172.16.0.0/16"
}
