terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

# 現在のAWSアカウント情報（S3バケット名のサフィックスに使用）
data "aws_caller_identity" "current" {}
