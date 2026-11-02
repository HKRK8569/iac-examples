# 共通
variable "multi_az" {
  description = "冗長化フラグ。falseにするとECSタスクを1つ・Auroraのreaderを0台に減らす（devコスト削減用）"
  type        = bool
  default     = true
}

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

# CloudFrontからのオリジンアクセス検証
variable "origin_verify_secret" {
  description = "CloudFrontがX-Origin-Verifyヘッダーに付与する秘密値。edgeモジュールと同じ値を指定する"
  type        = string
  sensitive   = true
  nullable    = false

  validation {
    # ALBのヘッダー条件でワイルドカードとして解釈される * / ? も許可しない。
    condition     = can(regex("^[A-Za-z0-9]{32,128}$", var.origin_verify_secret))
    error_message = "origin_verify_secretには32〜128文字のランダムな半角英数字を指定してください。"
  }
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
