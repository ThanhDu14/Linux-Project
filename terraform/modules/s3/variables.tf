# Variables for s3 module

variable "project_name" {
  type        = string
  description = "Project name prefix"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g. shared)"
}

variable "backup_bucket_name" {
  type        = string
  description = "Explicit name for the backup S3 bucket"
}

variable "backup_retention_days" {
  type        = number
  description = "Number of days after which backup objects are expired"
  default     = 30
}
