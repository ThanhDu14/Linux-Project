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
  description = "VPC ID where Security Groups are created"
}

variable "admin_cidrs" {
  type        = list(string)
  description = "List of admin CIDRs allowed to SSH into Bastion"
}
