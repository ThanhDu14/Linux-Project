# EC2 instance + optional EBS data volume + optional Elastic IP

# Data source: Ubuntu 22.04 LTS AMI (Canonical)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# EC2 instance
resource "aws_instance" "this" {
  # checkov:skip=CKV_AWS_135: "EBS optimization enabled by default on t3 family"
  # checkov:skip=CKV_AWS_126: "Detailed monitoring (1-min) costs extra; health-check scripts on the hosts cover monitoring for the lab"
  # checkov:skip=CKV_AWS_189: "Root volume encrypted with AWS-managed key; KMS CMK incurs unnecessary cost for lab"
  # checkov:skip=CKV2_AWS_41: "Only VM2 needs AWS API access (S3); Bastion and VM1 intentionally have no IAM role"
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  private_ip             = var.private_ip
  key_name               = var.key_name
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.iam_instance_profile_name != "" ? var.iam_instance_profile_name : null

  # Disable source/dest check only for NAT instances; kept default (true) here
  source_dest_check = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name        = "${var.project_name}-${var.name}-root"
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }

  metadata_options {
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  tags = {
    Name        = "${var.project_name}-${var.name}"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  # AMI lấy theo most_recent: không thay máy mỗi khi Canonical ra AMI mới.
  # Muốn lên AMI mới thì chủ động: terraform apply -replace=module.<tên>.aws_instance.this
  lifecycle {
    ignore_changes = [ami]
  }
}

# Optional EBS data volume (for VM1 /data and VM2 /backup)
resource "aws_ebs_volume" "data" {
  # checkov:skip=CKV_AWS_189: "Encrypted with AWS-managed key; KMS CMK incurs unnecessary cost for lab"
  count = var.data_volume_size > 0 ? 1 : 0

  availability_zone = var.availability_zone
  size              = var.data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name        = "${var.project_name}-${var.name}-data"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_volume_attachment" "data" {
  count = var.data_volume_size > 0 ? 1 : 0

  device_name = var.data_volume_device
  volume_id   = aws_ebs_volume.data[0].id
  instance_id = aws_instance.this.id

  # Dừng máy trước khi tháo ổ để destroy không bị treo khi ổ đang mount
  stop_instance_before_detaching = true
}

# Optional Elastic IP (for Bastion)
resource "aws_eip" "this" {
  count    = var.enable_eip ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.this.id

  tags = {
    Name        = "${var.project_name}-${var.name}-eip"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}


