output "state_bucket_name" {
  description = "The name of the S3 bucket created for Terraform state storage"
  value       = aws_s3_bucket.tfstate.bucket
}

output "state_bucket_arn" {
  description = "The ARN of the S3 bucket created for Terraform state storage"
  value       = aws_s3_bucket.tfstate.arn
}

output "aws_region" {
  description = "The AWS region where the state bucket is located"
  value       = var.aws_region
}
