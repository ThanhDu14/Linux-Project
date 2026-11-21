# environments/shared/backend.tf
# Partial backend: bucket và region truyền qua -backend-config khi terraform init
# Lệnh init mẫu:
#   terraform init -reconfigure \
#     -backend-config="bucket=${STATE_BUCKET}" \
#     -backend-config="region=${AWS_REGION}"

terraform {
  required_version = ">= 1.10.0" # use_lockfile (S3 native locking) cần >= 1.10

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    key          = "shared/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
