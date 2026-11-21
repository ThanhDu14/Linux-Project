# Outputs for route53 module

output "record_fqdns" {
  description = "FQDNs of the alias records"
  value       = [for r in aws_route53_record.alias_a : r.fqdn]
}
