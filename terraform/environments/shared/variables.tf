# Variables for shared environment

variable "aws_region" {
  type        = string
  description = "AWS region for provisioning shared resources"
  default     = "ap-southeast-1"
}

variable "project_name" {
  type        = string
  description = "Project name prefix used for resource naming"
  default     = "linux-project"
}

variable "environment" {
  type        = string
  description = "Environment label applied to tags"
  default     = "shared"
}

variable "backup_retention_days" {
  type        = number
  description = "Number of days to retain backup objects in S3 before expiry"
  default     = 30
}
