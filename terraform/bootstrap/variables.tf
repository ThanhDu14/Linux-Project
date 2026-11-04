variable "aws_region" {
  type        = string
  description = "AWS region for provisioning the bootstrap resources"
  default     = "ap-southeast-1"
}

variable "project_name" {
  type        = string
  description = "Project name prefix used for resource naming"
  default     = "linux-project"
}

variable "state_bucket_name" {
  type        = string
  description = "Explicit name for the Terraform state S3 bucket (leave empty to auto-generate from project name and account ID)"
  default     = ""
}
