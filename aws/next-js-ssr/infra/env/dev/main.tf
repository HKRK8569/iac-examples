terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }

  # TODO: 本番運用時はS3バックエンドに切り替える
  # backend "s3" { ... }
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

# TODO: edgeモジュールの配線が終わったら追加する
# module "edge" {
#   source = "../../modules/edge"
#   ...
# }
