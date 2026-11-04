# Variables for iam module

variable "project_name" {
  type        = string
  description = "Project name prefix"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g. shared)"
}

variable "backup_bucket_arn" {
  type        = string
  description = "ARN of the backup S3 bucket that VM2 is allowed to write to"
}
