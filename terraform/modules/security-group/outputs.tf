# Outputs for security-group module

output "sg_nlb_id" {
  description = "Security Group ID for NLB"
  value       = aws_security_group.nlb.id
}

output "sg_bastion_id" {
  description = "Security Group ID for Bastion"
  value       = aws_security_group.bastion.id
}

output "sg_vm1_id" {
  description = "Security Group ID for VM1 (web-app-db-01)"
  value       = aws_security_group.vm1.id
}

output "sg_vm2_id" {
  description = "Security Group ID for VM2 (backup-01)"
  value       = aws_security_group.vm2.id
}
