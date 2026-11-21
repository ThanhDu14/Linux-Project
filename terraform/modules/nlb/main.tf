# NLB (Network Load Balancer): TCP listeners 80 and 443, targeting VM1
# All resources use count = var.enable_nlb ? 1 : 0 to allow cost-saving toggle.

resource "aws_lb" "this" {
  # checkov:skip=CKV_AWS_152: "NLB cross-zone load balancing disabled; single-AZ lab does not need it"
  # checkov:skip=CKV_AWS_91: "NLB access logging disabled to reduce S3 costs in lab environment"
  # checkov:skip=CKV2_AWS_20: "Not an ALB; NLB is TCP passthrough and Nginx on VM1 does the HTTP->HTTPS 301"
  count = var.enable_nlb ? 1 : 0

  name               = "${var.project_name}-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [var.public_subnet_id]

  # SG chỉ gắn được vào NLB lúc tạo; sg-vm1 chỉ nhận 80/443 từ SG này
  security_groups = [var.sg_nlb_id]

  enable_deletion_protection = false

  tags = {
    Name        = "${var.project_name}-nlb"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Target group for HTTP (port 80)
resource "aws_lb_target_group" "http" {
  count = var.enable_nlb ? 1 : 0

  name        = "${var.project_name}-tg-http"
  port        = 80
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = {
    Name        = "${var.project_name}-tg-http"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Target group for HTTPS (port 443)
resource "aws_lb_target_group" "https" {
  count = var.enable_nlb ? 1 : 0

  name        = "${var.project_name}-tg-https"
  port        = 443
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    protocol            = "HTTPS"
    port                = "443"
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = {
    Name        = "${var.project_name}-tg-https"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Register VM1 as target for HTTP
resource "aws_lb_target_group_attachment" "vm1_http" {
  count = var.enable_nlb ? 1 : 0

  target_group_arn = aws_lb_target_group.http[0].arn
  target_id        = var.vm1_instance_id
  port             = 80
}

# Register VM1 as target for HTTPS
resource "aws_lb_target_group_attachment" "vm1_https" {
  count = var.enable_nlb ? 1 : 0

  target_group_arn = aws_lb_target_group.https[0].arn
  target_id        = var.vm1_instance_id
  port             = 443
}

# Listener: TCP port 80
resource "aws_lb_listener" "http" {
  count = var.enable_nlb ? 1 : 0

  load_balancer_arn = aws_lb.this[0].arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http[0].arn
  }

  tags = {
    Name        = "${var.project_name}-listener-http"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Listener: TCP port 443
resource "aws_lb_listener" "https" {
  count = var.enable_nlb ? 1 : 0

  load_balancer_arn = aws_lb.this[0].arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.https[0].arn
  }

  tags = {
    Name        = "${var.project_name}-listener-https"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
