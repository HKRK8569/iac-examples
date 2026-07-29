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

# TODO: appモジュールの配線が終わったら追加する
# module "app" {
#   source = "../../modules/app"
#   ...
# }

# TODO: edgeモジュールの配線が終わったら追加する
# module "edge" {
#   source = "../../modules/edge"
#   ...
# }
