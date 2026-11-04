variable "project_name" {
  type        = string
  description = "Project name prefix"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where NACLs are deployed"
}

variable "public_subnet_id" {
  type        = string
  description = "Subnet ID of the public subnet"
}

variable "private_subnet_id" {
  type        = string
  description = "Subnet ID of the private subnet"
}

variable "public_subnet_cidr" {
  type        = string
  description = "CIDR block of the public subnet"
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  type        = string
  description = "CIDR block of the private subnet"
  default     = "10.0.2.0/24"
}

variable "admin_cidrs" {
  type        = list(string)
  description = "List of administrator CIDRs allowed to SSH into Bastion"
}
