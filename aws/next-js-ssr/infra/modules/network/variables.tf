# 共通
variable "multi_az" {
  description = "冗長化フラグ。falseにするとNAT Gatewayを1台に減らす（devコスト削減用。サブネット自体は無料かつALB/Auroraの要件で2AZ分残す）"
  type        = bool
  default     = true
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}

variable "name_prefix" {
  description = "リソース命名のプレフィックス"
  type        = string
}

# VPC
variable "vpc_cidr" {
  description = "VPC の CIDR (例: 10.0.0.0/16)"
  type        = string
}

# subnet
variable "azs" {
  description = "使うAZを指定（例: ['ap-northeast-1a','ap-northeast-1c']）"
  type        = list(string)
}
variable "public_subnet_cidrs" {
  description = "パブリックサブネットのサイダーを指定（例: ['10.0.1.0/24','10.0.2.0/24']）"
  type        = list(string)
}

variable "app_subnet_cidrs" {
  description = "アプリ用プライベートサブネットのサイダーを指定（例: ['10.0.101.0/24','10.0.102.0/24']）"
  type        = list(string)
}

variable "db_subnet_cidrs" {
  description = "DB用プライベートサブネットのサイダーを指定（例: ['10.0.201.0/24','10.0.202.0/24']）"
  type        = list(string)
}
