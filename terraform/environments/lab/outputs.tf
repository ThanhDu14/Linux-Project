# Outputs for lab environment

output "bastion_public_ip" {
  description = "Public (Elastic) IP of the Bastion host — use for SSH entry point"
  value       = module.bastion.public_ip
}

output "bastion_private_ip" {
  description = "Private IP of the Bastion host"
  value       = module.bastion.private_ip
}

output "vm1_private_ip" {
  description = "Private IP of VM1 (web-app-db-01)"
  value       = module.vm1.private_ip
}

output "vm2_private_ip" {
  description = "Private IP of VM2 (backup-01)"
  value       = module.vm2.private_ip
}

output "nlb_dns_name" {
  description = "DNS name of the NLB — use for curl tests (empty if enable_nlb = false)"
  value       = module.nlb.nlb_dns_name
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "web_domains" {
  description = "Tên miền của 2 vhost (Ansible nhận qua inventory). Không có domain_name → *.lab.local, curl bằng NLB DNS + Host header"
  value = {
    app    = local.app_domain
    status = local.status_domain
    dns    = local.enable_dns ? "Route 53 → NLB" : "không có bản ghi DNS"
  }
}
