# 共通
variable "multi_az" {
  description = "冗長化フラグ。falseにするとNAT 1台・ECSタスク1つ・Auroraのreader 0台になる（1人での検証用）。サブネットはALB/Auroraの要件により常に2AZ分作られる"
  type        = bool
  default     = true
}

variable "region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "name_prefix" {
  description = "リソース命名のプレフィックス（環境名を含める 例: next-js-ssr-dev）"
  type        = string
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}

# VPC
variable "vpc_cidr" {
  description = "VPCのCIDR (例: 10.0.0.0/16)"
  type        = string
}

# subnet
variable "azs" {
  description = "使うAZを指定（例: ['ap-northeast-1a','ap-northeast-1c']）"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "パブリックサブネットのCIDR一覧"
  type        = list(string)
}

variable "app_subnet_cidrs" {
  description = "アプリ用プライベートサブネットのCIDR一覧（ECS・踏み台を配置）"
  type        = list(string)
}

variable "db_subnet_cidrs" {
  description = "DB用プライベートサブネットのCIDR一覧（Auroraを配置。NATへのルートなし）"
  type        = list(string)
}

# aurora
variable "db_name" {
  description = "DB名"
  type        = string
}

variable "db_username" {
  description = "DBのユーザー名"
  type        = string
}

variable "db_password" {
  description = "DBのパスワード"
  type        = string
  sensitive   = true
}

# ecs
variable "container_port" {
  description = "コンテナのポート"
  type        = number
  default     = 3000
}

variable "container_image" {
  description = "コンテナイメージ（ECRのURI:タグ）"
  type        = string
}
