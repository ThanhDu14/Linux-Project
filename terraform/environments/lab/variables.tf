# Variables for lab environment

variable "aws_region" {
  type        = string
  description = "AWS region for provisioning lab resources"
  default     = "ap-southeast-1"
}

variable "project_name" {
  type        = string
  description = "Project name prefix used for all resource names"
  default     = "linux-project"
}

variable "environment" {
  type        = string
  description = "Environment label applied to tags"
  default     = "lab"
}

variable "state_bucket" {
  type        = string
  description = "Name of the S3 bucket storing Terraform state (from bootstrap output)"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type        = string
  description = "CIDR block for the public subnet"
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  type        = string
  description = "CIDR block for the private subnet"
  default     = "10.0.2.0/24"
}

variable "availability_zone" {
  type        = string
  description = "Availability Zone for all resources"
  default     = "ap-southeast-1a"
}

variable "enable_nat" {
  type        = bool
  description = "Set to true to create a NAT Gateway (required for apt/pip/SMTP; costs ~0.059 USD/hr)"
  default     = false
}

variable "enable_nlb" {
  type        = bool
  description = "Set to true to create the Network Load Balancer (required for demo; costs ~0.025 USD/hr)"
  default     = false
}

variable "key_name" {
  type        = string
  description = "EC2 Key Pair name for SSH access to all instances"
}

variable "admin_cidrs" {
  type        = list(string)
  description = "List of CIDRs allowed to SSH into the Bastion host (e.g. your home IP /32)"

  validation {
    condition     = length(var.admin_cidrs) >= 1 && length(var.admin_cidrs) <= 10
    error_message = "admin_cidrs phải có từ 1 đến 10 CIDR (NACL dành sẵn rule 120-129 cho SSH)."
  }

  validation {
    condition     = alltrue([for c in var.admin_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "Mỗi phần tử admin_cidrs phải là CIDR hợp lệ (vd 1.2.3.4/32) và không được là 0.0.0.0/0."
  }
}

variable "ssh_private_key_path" {
  type        = string
  description = "Local path to the private key of key_name; written into the Ansible inventory"
  default     = "~/.ssh/linux-project-key.pem"
}
