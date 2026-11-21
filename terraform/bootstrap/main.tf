terraform {
  required_version = ">= 1.10.0" # đồng bộ với environments (use_lockfile cần >= 1.10)
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      Component = "bootstrap"
      ManagedBy = "Terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  bucket_name = length(var.state_bucket_name) > 0 ? var.state_bucket_name : "${var.project_name}-terraform-state-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "tfstate" {
  # checkov:skip=CKV_AWS_18: "State bucket access logging is omitted for cost optimization in educational lab"
  # checkov:skip=CKV_AWS_144: "Cross-region replication not required for lab environment"
  # checkov:skip=CKV_AWS_145: "SSE-S3 (AES256) is sufficient; KMS CMK incurs unnecessary costs for lab"
  # checkov:skip=CKV2_AWS_61: "Lifecycle configuration not applied to keep state history intact"
  # checkov:skip=CKV2_AWS_62: "Bucket event notification not required"
  bucket = local.bucket_name

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = local.bucket_name
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
