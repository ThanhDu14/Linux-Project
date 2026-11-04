# Variables for ec2 module

variable "project_name" {
  type        = string
  description = "Project name prefix used for resource naming"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g. lab, shared)"
}

variable "name" {
  type        = string
  description = "Short name for this instance (e.g. bastion, vm1, vm2). Used in resource Name tag."
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type (e.g. t3.micro, t3.small)"
  default     = "t3.micro"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID to launch the instance into"
}

variable "private_ip" {
  type        = string
  description = "Fixed private IP address within the subnet (e.g. 10.0.1.10)"
}

variable "key_name" {
  type        = string
  description = "EC2 Key Pair name for SSH access"
}

variable "security_group_ids" {
  type        = list(string)
  description = "List of Security Group IDs to attach to the instance"
}

variable "availability_zone" {
  type        = string
  description = "AZ for EBS volume creation (must match instance AZ)"
}

variable "data_volume_size" {
  type        = number
  description = "Size of the additional EBS data volume in GiB. Set to 0 to skip."
  default     = 0
}

variable "data_volume_device" {
  type        = string
  description = "Device name for EBS data volume attachment (e.g. /dev/xvdf)"
  default     = "/dev/xvdf"
}

variable "enable_eip" {
  type        = bool
  description = "Whether to allocate and associate an Elastic IP for this instance (use for Bastion)"
  default     = false
}

variable "iam_instance_profile_name" {
  type        = string
  description = "IAM instance profile name to attach to the instance. Leave empty string to skip."
  default     = ""
}
