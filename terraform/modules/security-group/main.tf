# Security Groups: sg-nlb, sg-bastion, sg-vm1, sg-vm2

# ----- sg-nlb -----
resource "aws_security_group" "nlb" {
  # checkov:skip=CKV2_AWS_5: "Attached to the NLB in environments/lab via module output sg_nlb_id"
  name        = "${var.project_name}-sg-nlb"
  description = "Security group for NLB: allow HTTP/HTTPS from Internet"
  vpc_id      = var.vpc_id


  tags = {
    Name        = "${var.project_name}-sg-nlb"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_vpc_security_group_ingress_rule" "nlb_in_http" {
  # checkov:skip=CKV_AWS_260: "Public web entry point; NLB must accept HTTP from Internet so Nginx can 301 to HTTPS"
  security_group_id = aws_security_group.nlb.id
  description       = "Allow HTTP from Internet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "nlb_in_https" {
  security_group_id = aws_security_group.nlb.id
  description       = "Allow HTTPS from Internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "nlb_out_http_to_vm1" {
  security_group_id            = aws_security_group.nlb.id
  description                  = "Forward HTTP to VM1"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.vm1.id
}

resource "aws_vpc_security_group_egress_rule" "nlb_out_https_to_vm1" {
  security_group_id            = aws_security_group.nlb.id
  description                  = "Forward HTTPS to VM1"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.vm1.id
}

# ----- sg-bastion -----
resource "aws_security_group" "bastion" {
  # checkov:skip=CKV2_AWS_5: "Attached to bastion-01 in environments/lab via module output sg_bastion_id"
  name        = "${var.project_name}-sg-bastion"
  description = "Security group for Bastion: SSH from admin IPs only"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "${var.project_name}-sg-bastion"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_vpc_security_group_ingress_rule" "bastion_in_ssh" {
  for_each = toset(var.admin_cidrs)

  security_group_id = aws_security_group.bastion.id
  description       = "Allow SSH from admin CIDR"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "bastion_out_ssh_vm1" {
  security_group_id            = aws_security_group.bastion.id
  description                  = "ProxyJump SSH to VM1"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.vm1.id
}

resource "aws_vpc_security_group_egress_rule" "bastion_out_ssh_vm2" {
  security_group_id            = aws_security_group.bastion.id
  description                  = "ProxyJump SSH to VM2"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.vm2.id
}

resource "aws_vpc_security_group_egress_rule" "bastion_out_http" {
  security_group_id = aws_security_group.bastion.id
  description       = "Allow HTTP out for apt"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "bastion_out_https" {
  security_group_id = aws_security_group.bastion.id
  description       = "Allow HTTPS out for apt"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "bastion_out_smtp" {
  security_group_id = aws_security_group.bastion.id
  description       = "Allow SMTP out for mail alerts"
  ip_protocol       = "tcp"
  from_port         = 587
  to_port           = 587
  cidr_ipv4         = "0.0.0.0/0"
}

# ----- sg-vm1 (web-app-db-01) -----
resource "aws_security_group" "vm1" {
  # checkov:skip=CKV2_AWS_5: "Attached to web-app-db-01 in environments/lab via module output sg_vm1_id"
  name        = "${var.project_name}-sg-vm1"
  description = "Security group for VM1 (Nginx+Flask+PostgreSQL)"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "${var.project_name}-sg-vm1"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_vpc_security_group_ingress_rule" "vm1_in_http_nlb" {
  # checkov:skip=CKV_AWS_260: "False positive: source is sg-nlb (referenced_security_group_id), not 0.0.0.0/0"
  security_group_id            = aws_security_group.vm1.id
  description                  = "Allow HTTP from NLB"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.nlb.id
}

resource "aws_vpc_security_group_ingress_rule" "vm1_in_https_nlb" {
  security_group_id            = aws_security_group.vm1.id
  description                  = "Allow HTTPS from NLB"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.nlb.id
}

resource "aws_vpc_security_group_ingress_rule" "vm1_in_https_vm2" {
  security_group_id            = aws_security_group.vm1.id
  description                  = "Allow HTTPS health-check from VM2"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.vm2.id
}

resource "aws_vpc_security_group_ingress_rule" "vm1_in_ssh_bastion" {
  # checkov:skip=CKV_AWS_24: "False positive: source is sg-bastion (referenced_security_group_id), not 0.0.0.0/0"
  security_group_id            = aws_security_group.vm1.id
  description                  = "Allow SSH from Bastion"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.bastion.id
}

resource "aws_vpc_security_group_egress_rule" "vm1_out_ssh_vm2" {
  security_group_id            = aws_security_group.vm1.id
  description                  = "Allow SSH/rsync to VM2"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.vm2.id
}

resource "aws_vpc_security_group_egress_rule" "vm1_out_http" {
  security_group_id = aws_security_group.vm1.id
  description       = "Allow HTTP out for apt/pip via NAT"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "vm1_out_https" {
  security_group_id = aws_security_group.vm1.id
  description       = "Allow HTTPS out for apt/pip/S3 via NAT"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "vm1_out_smtp" {
  security_group_id = aws_security_group.vm1.id
  description       = "Allow SMTP out for msmtp alerts"
  ip_protocol       = "tcp"
  from_port         = 587
  to_port           = 587
  cidr_ipv4         = "0.0.0.0/0"
}

# ----- sg-vm2 (backup-01) -----
resource "aws_security_group" "vm2" {
  # checkov:skip=CKV2_AWS_5: "Attached to backup-01 in environments/lab via module output sg_vm2_id"
  name        = "${var.project_name}-sg-vm2"
  description = "Security group for VM2 (backup + health-check)"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "${var.project_name}-sg-vm2"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_vpc_security_group_ingress_rule" "vm2_in_ssh_bastion" {
  # checkov:skip=CKV_AWS_24: "False positive: source is sg-bastion (referenced_security_group_id), not 0.0.0.0/0"
  security_group_id            = aws_security_group.vm2.id
  description                  = "Allow SSH from Bastion"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.bastion.id
}

resource "aws_vpc_security_group_ingress_rule" "vm2_in_ssh_vm1" {
  # checkov:skip=CKV_AWS_24: "False positive: source is sg-vm1 (referenced_security_group_id), not 0.0.0.0/0"
  security_group_id            = aws_security_group.vm2.id
  description                  = "Allow SSH/rsync from VM1"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.vm1.id
}

resource "aws_vpc_security_group_egress_rule" "vm2_out_https_vm1" {
  security_group_id            = aws_security_group.vm2.id
  description                  = "Allow HTTPS health-check to VM1"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.vm1.id
}

resource "aws_vpc_security_group_egress_rule" "vm2_out_http" {
  security_group_id = aws_security_group.vm2.id
  description       = "Allow HTTP out for apt via NAT"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "vm2_out_https" {
  security_group_id = aws_security_group.vm2.id
  description       = "Allow HTTPS out for apt/S3 via NAT/endpoint"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "vm2_out_smtp" {
  security_group_id = aws_security_group.vm2.id
  description       = "Allow SMTP out for msmtp alerts"
  ip_protocol       = "tcp"
  from_port         = 587
  to_port           = 587
  cidr_ipv4         = "0.0.0.0/0"
}
