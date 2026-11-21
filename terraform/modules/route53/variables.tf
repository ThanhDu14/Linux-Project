# Variables for route53 module

variable "route53_zone_id" {
  type        = string
  description = "Zone ID of the Route 53 hosted zone"
}

variable "record_names" {
  type        = list(string)
  description = "Fully qualified names of the alias records (e.g. app.example.click, status.example.click)"
}

variable "nlb_dns_name" {
  type        = string
  description = "DNS name of the NLB"
}

variable "nlb_zone_id" {
  type        = string
  description = "Hosted zone ID of the NLB (for alias records)"
}
