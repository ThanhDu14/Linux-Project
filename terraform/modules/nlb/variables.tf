# Variables for nlb module

variable "project_name" {
  type        = string
  description = "Project name prefix used for resource naming"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g. lab)"
}

variable "enable_nlb" {
  type        = bool
  description = "Set to false to skip NLB creation (cost saving when not demoing)"
  default     = true
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the NLB and target groups are created"
}

variable "public_subnet_id" {
  type        = string
  description = "Public subnet ID for the NLB"
}

variable "sg_nlb_id" {
  type        = string
  description = "Security Group ID (sg-nlb) attached to the NLB; sg-vm1 only accepts web traffic from it"
}

variable "vm1_instance_id" {
  type        = string
  description = "EC2 Instance ID of VM1 (web-app-db-01) to register as NLB target"
}
