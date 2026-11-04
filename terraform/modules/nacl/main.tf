# Public Subnet NACL
resource "aws_network_acl" "public" {
  # checkov:skip=CKV2_AWS_1: "False positive: attached via subnet_ids = [var.public_subnet_id]"
  vpc_id     = var.vpc_id
  subnet_ids = [var.public_subnet_id]

  tags = {
    Name        = "${var.project_name}-nacl-public"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Ingress Rules - Public NACL
resource "aws_network_acl_rule" "public_in_http" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = false
  protocol       = "6" # TCP
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "public_in_https" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 110
  egress         = false
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "public_in_ssh" {
  count          = length(var.admin_cidrs)
  network_acl_id = aws_network_acl.public.id
  rule_number    = 120 + count.index
  egress         = false
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = var.admin_cidrs[count.index]
  from_port      = 22
  to_port        = 22
}

resource "aws_network_acl_rule" "public_in_smtp" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 130
  egress         = false
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = var.private_subnet_cidr
  from_port      = 587
  to_port        = 587
}

resource "aws_network_acl_rule" "public_in_ephemeral" {
  # checkov:skip=CKV_AWS_231: "Stateless NACL needs return traffic on ephemeral 1024-65535 (includes 3389); no host listens on 3389 and SG blocks it"
  network_acl_id = aws_network_acl.public.id
  rule_number    = 140
  egress         = false
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# Egress Rules - Public NACL
resource "aws_network_acl_rule" "public_out_http" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = true
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "public_out_https" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 110
  egress         = true
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "public_out_smtp" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 120
  egress         = true
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 587
  to_port        = 587
}

resource "aws_network_acl_rule" "public_out_ssh_to_private" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 130
  egress         = true
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = var.private_subnet_cidr
  from_port      = 22
  to_port        = 22
}

resource "aws_network_acl_rule" "public_out_ephemeral" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 140
  egress         = true
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# Private Subnet NACL
resource "aws_network_acl" "private" {
  # checkov:skip=CKV2_AWS_1: "False positive: attached via subnet_ids = [var.private_subnet_id]"
  vpc_id     = var.vpc_id
  subnet_ids = [var.private_subnet_id]

  tags = {
    Name        = "${var.project_name}-nacl-private"
    Project     = var.project_name
    Environment = var.environment
  }
}

# Ingress Rules - Private NACL
resource "aws_network_acl_rule" "private_in_http" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = false
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "private_in_https" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 110
  egress         = false
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "private_in_ssh" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 120
  egress         = false
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = var.public_subnet_cidr
  from_port      = 22
  to_port        = 22
}

resource "aws_network_acl_rule" "private_in_ephemeral" {
  # checkov:skip=CKV_AWS_231: "Stateless NACL needs return traffic on ephemeral 1024-65535 (includes 3389); no host listens on 3389 and SG blocks it"
  network_acl_id = aws_network_acl.private.id
  rule_number    = 130
  egress         = false
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# Egress Rules - Private NACL
resource "aws_network_acl_rule" "private_out_http" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = true
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "private_out_https" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 110
  egress         = true
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "private_out_smtp" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 120
  egress         = true
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 587
  to_port        = 587
}

resource "aws_network_acl_rule" "private_out_ephemeral" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 130
  egress         = true
  protocol       = "6"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}
