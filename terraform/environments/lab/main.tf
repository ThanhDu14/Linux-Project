# environments/lab/main.tf
# Tài nguyên dựng/huỷ hằng ngày: VPC, NACL, Security Group, EC2, NLB.
# Đọc output từ môi trường shared qua terraform_remote_state.

# Đọc state của môi trường shared để lấy IAM instance profile cho VM2
data "terraform_remote_state" "shared" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "shared/terraform.tfstate"
    region = var.aws_region
  }
}

# 1. VPC Module
module "vpc" {
  source = "../../modules/vpc"

  project_name        = var.project_name
  environment         = var.environment
  aws_region          = var.aws_region
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  availability_zone   = var.availability_zone
  enable_nat          = var.enable_nat
}

# 2. NACL Module
module "nacl" {
  source = "../../modules/nacl"

  project_name        = var.project_name
  environment         = var.environment
  vpc_id              = module.vpc.vpc_id
  public_subnet_id    = module.vpc.public_subnet_id
  private_subnet_id   = module.vpc.private_subnet_id
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  admin_cidrs         = var.admin_cidrs
}

# 3. Security Group Module
module "security_group" {
  source = "../../modules/security-group"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  admin_cidrs  = var.admin_cidrs
}

# 4. EC2 Module — Bastion (public subnet, Elastic IP, no data volume)
module "bastion" {
  source = "../../modules/ec2"

  project_name       = var.project_name
  environment        = var.environment
  name               = "bastion-01"
  instance_type      = "t3.micro"
  subnet_id          = module.vpc.public_subnet_id
  private_ip         = cidrhost(var.public_subnet_cidr, 10) # 10.0.1.10
  key_name           = var.key_name
  security_group_ids = [module.security_group.sg_bastion_id]
  availability_zone  = var.availability_zone
  enable_eip         = true
}

# 5. EC2 Module — VM1 web-app-db-01 (private subnet, EBS 10 GB /data)
module "vm1" {
  source = "../../modules/ec2"

  project_name       = var.project_name
  environment        = var.environment
  name               = "web-app-db-01"
  instance_type      = "t3.small"
  subnet_id          = module.vpc.private_subnet_id
  private_ip         = cidrhost(var.private_subnet_cidr, 10) # 10.0.2.10
  key_name           = var.key_name
  security_group_ids = [module.security_group.sg_vm1_id]
  availability_zone  = var.availability_zone
  data_volume_size   = 10
  data_volume_device = "/dev/xvdf"
}

# 6. EC2 Module — VM2 backup-01 (private subnet, EBS 20 GB /backup, IAM profile)
module "vm2" {
  source = "../../modules/ec2"

  project_name              = var.project_name
  environment               = var.environment
  name                      = "backup-01"
  instance_type             = "t3.micro"
  subnet_id                 = module.vpc.private_subnet_id
  private_ip                = cidrhost(var.private_subnet_cidr, 20) # 10.0.2.20
  key_name                  = var.key_name
  security_group_ids        = [module.security_group.sg_vm2_id]
  availability_zone         = var.availability_zone
  data_volume_size          = 20
  data_volume_device        = "/dev/xvdf"
  iam_instance_profile_name = data.terraform_remote_state.shared.outputs.vm2_instance_profile_name
}

# 7. NLB Module (bật/tắt bằng enable_nlb)
module "nlb" {
  source = "../../modules/nlb"

  project_name     = var.project_name
  environment      = var.environment
  enable_nlb       = var.enable_nlb
  vpc_id           = module.vpc.vpc_id
  public_subnet_id = module.vpc.public_subnet_id
  sg_nlb_id        = module.security_group.sg_nlb_id
  vm1_instance_id  = module.vm1.instance_id
}
