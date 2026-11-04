# IAM role and instance profile for VM2 to push backups to S3

# Trust policy: allow EC2 to assume this role
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# IAM role for backup instance
resource "aws_iam_role" "backup" {
  name               = "${var.project_name}-backup-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name        = "${var.project_name}-backup-role"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Inline policy: allow VM2 to sync backup files to S3
data "aws_iam_policy_document" "backup_s3" {
  statement {
    sid    = "AllowS3BackupSync"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
    ]
    resources = ["${var.backup_bucket_arn}/*"]
  }

  statement {
    sid       = "AllowS3ListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [var.backup_bucket_arn]
  }
}

resource "aws_iam_role_policy" "backup_s3" {
  name   = "${var.project_name}-backup-s3-policy"
  role   = aws_iam_role.backup.id
  policy = data.aws_iam_policy_document.backup_s3.json
}

# Instance profile wrapping the role (attached to VM2 EC2 instance)
resource "aws_iam_instance_profile" "backup" {
  name = "${var.project_name}-backup-profile"
  role = aws_iam_role.backup.name

  tags = {
    Name        = "${var.project_name}-backup-profile"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
