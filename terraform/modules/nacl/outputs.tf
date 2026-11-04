output "public_nacl_id" {
  description = "The ID of the Public Subnet Network ACL"
  value       = aws_network_acl.public.id
}

output "private_nacl_id" {
  description = "The ID of the Private Subnet Network ACL"
  value       = aws_network_acl.private.id
}
