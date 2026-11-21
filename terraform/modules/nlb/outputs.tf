# Outputs for nlb module

output "nlb_dns_name" {
  description = "DNS name of the NLB (empty string if enable_nlb = false)"
  value       = var.enable_nlb ? aws_lb.this[0].dns_name : ""
}

output "nlb_arn" {
  description = "ARN of the NLB (empty string if enable_nlb = false)"
  value       = var.enable_nlb ? aws_lb.this[0].arn : ""
}

output "nlb_zone_id" {
  description = "Hosted zone ID of the NLB for Route53 alias records"
  value       = var.enable_nlb ? aws_lb.this[0].zone_id : ""
}
