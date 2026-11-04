output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_id" {
  description = "The ID of the public subnet"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "The ID of the private subnet"
  value       = aws_subnet.private.id
}

output "public_route_table_id" {
  description = "The ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "The ID of the private route table"
  value       = aws_route_table.private.id
}

output "nat_gateway_id" {
  description = "The ID of the NAT Gateway (if enabled)"
  value       = var.enable_nat ? aws_nat_gateway.this[0].id : null
}

output "nat_gateway_public_ip" {
  description = "The public IP allocated to the NAT Gateway (if enabled)"
  value       = var.enable_nat ? aws_eip.nat[0].public_ip : null
}

output "s3_endpoint_id" {
  description = "The ID of the S3 Gateway VPC endpoint"
  value       = aws_vpc_endpoint.s3.id
}
