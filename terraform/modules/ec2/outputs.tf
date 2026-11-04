# Outputs for ec2 module

output "instance_id" {
  description = "EC2 Instance ID"
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Private IP address of the instance"
  value       = aws_instance.this.private_ip
}

output "public_ip" {
  description = "Elastic IP address (empty string if enable_eip = false)"
  value       = var.enable_eip ? aws_eip.this[0].public_ip : ""
}

output "eip_allocation_id" {
  description = "EIP allocation ID (empty string if enable_eip = false)"
  value       = var.enable_eip ? aws_eip.this[0].allocation_id : ""
}
