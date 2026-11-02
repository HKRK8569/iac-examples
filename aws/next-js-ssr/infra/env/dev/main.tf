terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # tfstate用のバケットは事前に手動で作成しておく（手順はREADME参照）
  # bucketはアカウントIDを含むためここに直書きせず、
  # dev.s3.tfbackend に記載して init 時に -backend-config で渡す（README参照）
  backend "s3" {
    key          = "dev/terraform.tfstate"
    region       = "ap-northeast-1"
    use_lockfile = true
  }
}

# リージョン
provider "aws" {
  region = var.region
}

# CloudFront用WAFはus-east-1で管理する。
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "network" {
  source = "../../modules/network"

  name_prefix = var.name_prefix
  tags        = var.tags
  multi_az    = var.multi_az

  vpc_cidr            = var.vpc_cidr
  azs                 = var.azs
  public_subnet_cidrs = var.public_subnet_cidrs
  app_subnet_cidrs    = var.app_subnet_cidrs
  db_subnet_cidrs     = var.db_subnet_cidrs
}

module "bastion" {
  source = "../../modules/bastion"

  name_prefix = var.name_prefix
  tags        = var.tags

  auto_stop_enabled       = var.bastion_auto_stop_enabled
  auto_stop_after_minutes = var.bastion_auto_stop_after_minutes

  vpc_id = module.network.vpc_id
  # SSM接続にNATへの経路が必要なためappサブネットに配置（1AZに1台で十分）
  subnet_id = module.network.app_subnet_ids[0]
}

module "app" {
  source = "../../modules/app"

  name_prefix = var.name_prefix
  tags        = var.tags
  region      = var.region
  multi_az    = var.multi_az

  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  app_subnet_ids    = module.network.app_subnet_ids
  db_subnet_ids     = module.network.db_subnet_ids

  # 踏み台からAurora(5432)への接続を許可する
  bastion_security_group_id = module.bastion.security_group_id

  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password

  aurora_deletion_protection       = var.aurora_deletion_protection
  alb_deletion_protection          = var.alb_deletion_protection
  aurora_skip_final_snapshot       = var.aurora_skip_final_snapshot
  aurora_final_snapshot_identifier = var.aurora_final_snapshot_identifier

  container_port  = var.container_port
  container_image = var.container_image

  origin_verify_secret = random_password.origin_verify.result
}

module "edge" {
  source = "../../modules/edge"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name_prefix = var.name_prefix
  tags        = var.tags

  ip_restriction_enabled = var.cloudfront_ip_restriction_enabled
  allowed_ipv4_cidrs     = var.cloudfront_allowed_ipv4_cidrs
  allowed_ipv6_cidrs     = var.cloudfront_allowed_ipv6_cidrs

  origin_verify_secret = random_password.origin_verify.result

  alb_dns_name                       = module.app.alb_dns_name
  images_bucket_regional_domain_name = module.app.images_bucket_regional_domain_name
  images_bucket_id                   = module.app.images_bucket_name
  images_bucket_arn                  = module.app.images_bucket_arn
}
