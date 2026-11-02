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

# CloudFrontの閲覧者IP制限
variable "cloudfront_ip_restriction_enabled" {
  description = "CloudFrontへのアクセスを許可CIDRに限定する。trueの場合はIPv4・IPv6のいずれかに1件以上の許可CIDRが必要"
  type        = bool
  default     = false
  nullable    = false
}

variable "cloudfront_allowed_ipv4_cidrs" {
  description = "CloudFrontへのアクセスを許可するIPv4 CIDRの一覧（単一IPは/32、複数指定可能）"
  type        = set(string)
  default     = []
  nullable    = false
}

variable "cloudfront_allowed_ipv6_cidrs" {
  description = "CloudFrontへのアクセスを許可するIPv6 CIDRの一覧（単一IPは/128、複数指定可能）"
  type        = set(string)
  default     = []
  nullable    = false
}

# 踏み台の自動停止
variable "bastion_auto_stop_enabled" {
  description = "踏み台の自動停止を有効にする。devでは既定で有効"
  type        = bool
  default     = true
  nullable    = false
}

variable "bastion_auto_stop_after_minutes" {
  description = "踏み台の起動から自動停止までの分数（1〜1440の整数）。SSM接続中でも停止する"
  type        = number
  default     = 60
  nullable    = false
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

# 削除保護・最終スナップショット（入力の検証はappモジュールで行う）
variable "aurora_deletion_protection" {
  description = "Auroraクラスターの削除保護。prdではtrueにする"
  type        = bool
  default     = false
  nullable    = false
}

variable "alb_deletion_protection" {
  description = "ALBの削除保護。prdではtrueにする"
  type        = bool
  default     = false
  nullable    = false
}

variable "aurora_skip_final_snapshot" {
  description = "Aurora削除時に最終スナップショットを省略する。prdではfalseにする"
  type        = bool
  default     = true
  nullable    = false
}

variable "aurora_final_snapshot_identifier" {
  description = "Auroraの最終スナップショット名。aurora_skip_final_snapshot=falseの場合は必須"
  type        = string
  default     = null
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
