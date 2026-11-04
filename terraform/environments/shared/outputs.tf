# Outputs for shared environment

output "backup_bucket_name" {
  description = "Name of the S3 backup bucket"
  value       = module.s3.bucket_name
}

output "backup_bucket_arn" {
  description = "ARN of the S3 backup bucket"
  value       = module.s3.bucket_arn
}

output "vm2_instance_profile_name" {
  description = "IAM instance profile name to attach to VM2 (backup-01)"
  value       = module.iam.instance_profile_name
}

output "vm2_instance_profile_arn" {
  description = "ARN of the IAM instance profile for VM2"
  value       = module.iam.instance_profile_arn
}
