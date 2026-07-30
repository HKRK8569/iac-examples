terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
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

module "network" {
  source = "../../modules/network"

  name_prefix = var.name_prefix
  tags        = var.tags

  vpc_cidr            = var.vpc_cidr
  azs                 = var.azs
  public_subnet_cidrs = var.public_subnet_cidrs
  app_subnet_cidrs    = var.app_subnet_cidrs
  db_subnet_cidrs     = var.db_subnet_cidrs
}

module "app" {
  source = "../../modules/app"

  name_prefix = var.name_prefix
  tags        = var.tags
  region      = var.region

  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  app_subnet_ids    = module.network.app_subnet_ids
  db_subnet_ids     = module.network.db_subnet_ids

  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password

  container_port  = var.container_port
  container_image = var.container_image
}

module "edge" {
  source = "../../modules/edge"

  name_prefix = var.name_prefix
  tags        = var.tags

  alb_dns_name                       = module.app.alb_dns_name
  images_bucket_regional_domain_name = module.app.images_bucket_regional_domain_name
  images_bucket_id                   = module.app.images_bucket_name
  images_bucket_arn                  = module.app.images_bucket_arn
}
