terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

# 定数
locals {
  # natの数（冗長化ONなら各AZに1台、OFFなら全体で1台）
  nat_count = var.multi_az ? length(var.azs) : 1
}
