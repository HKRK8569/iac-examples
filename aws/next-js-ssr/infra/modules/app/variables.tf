# 共通
variable "region" {
  description = "AWSリージョン（CloudWatch Logsの出力先指定に使用）"
  type        = string
  default     = "ap-northeast-1"
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

# network（networkモジュールのoutputをルートから受け取る）
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "パブリックサブネットのID一覧（ALBを配置）"
  type        = list(string)
}

variable "app_subnet_ids" {
  description = "アプリ用プライベートサブネットのID一覧（ECSを配置）"
  type        = list(string)
}

variable "db_subnet_ids" {
  description = "DB用プライベートサブネットのID一覧（Auroraを配置）"
  type        = list(string)
}

# bastion
variable "bastion_security_group_id" {
  description = "踏み台のSG ID（指定するとAuroraへの5432を許可する。踏み台を置かない環境はnull）"
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
  description = "ecsのポート"
  type        = number
  default     = 3000
}

variable "container_image" {
  description = "コンテナイメージ（ECRのURI:タグ）"
  type        = string
}
