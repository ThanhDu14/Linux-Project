# Outputs for iam module

output "instance_profile_name" {
  description = "Name of the IAM instance profile to attach to VM2"
  value       = aws_iam_instance_profile.backup.name
}

output "instance_profile_arn" {
  description = "ARN of the IAM instance profile"
  value       = aws_iam_instance_profile.backup.arn
}

output "role_arn" {
  description = "ARN of the IAM role"
  value       = aws_iam_role.backup.arn
}
