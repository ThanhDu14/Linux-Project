# environments/shared/main.tf
# Tài nguyên sống lâu: S3 backup bucket + IAM role/instance profile cho VM2.
# KHÔNG destroy môi trường này hằng ngày — dùng riêng môi trường lab.

data "aws_caller_identity" "current" {}

locals {
  backup_bucket_name = "${var.project_name}-backup-${data.aws_caller_identity.current.account_id}"
}

# 1. S3 Backup Module
module "s3" {
  source = "../../modules/s3"

  project_name          = var.project_name
  environment           = var.environment
  backup_bucket_name    = local.backup_bucket_name
  backup_retention_days = var.backup_retention_days
}

# 2. IAM Module (instance profile cho VM2 → S3)
module "iam" {
  source = "../../modules/iam"

  project_name      = var.project_name
  environment       = var.environment
  backup_bucket_arn = module.s3.bucket_arn
}
