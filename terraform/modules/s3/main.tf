# S3 bucket for off-site backup storage with versioning, encryption, and lifecycle rules

resource "aws_s3_bucket" "backup" {
  # checkov:skip=CKV_AWS_18: "Backup bucket access logging omitted for cost optimization in lab environment"
  # checkov:skip=CKV_AWS_144: "Cross-region replication not required for lab environment"
  # checkov:skip=CKV_AWS_145: "SSE-S3 (AES256) is sufficient; KMS CMK incurs unnecessary cost for lab"
  # checkov:skip=CKV2_AWS_62: "Bucket event notification not required for lab"
  bucket = var.backup_bucket_name

  tags = {
    Name        = var.backup_bucket_name
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "backup" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning
resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption with AES256
resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle: expire current objects after backup_retention_days, noncurrent after 7 days,
# abort incomplete multipart uploads after 1 day
resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    id     = "expire-backups"
    status = "Enabled"

    # Áp dụng cho toàn bộ object (provider v5 cảnh báo nếu thiếu, v6 sẽ báo lỗi)
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }

    expiration {
      days = var.backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}
