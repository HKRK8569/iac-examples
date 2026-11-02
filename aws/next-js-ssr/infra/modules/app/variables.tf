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

# 削除保護・最終スナップショット
variable "aurora_deletion_protection" {
  description = "Auroraクラスターの削除保護。prdではtrueにする。DBインスタンス自体の削除は防がない"
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
  description = "Aurora削除時に最終スナップショットを省略する。prdではfalseにし、削除保護とは独立して設定する"
  type        = bool
  default     = true
  nullable    = false
}

variable "aurora_final_snapshot_identifier" {
  description = "Auroraの最終スナップショット名。保存する場合は必須。既存のスナップショットと重複しない名前を指定する"
  type        = string
  default     = null

  validation {
    condition     = var.aurora_skip_final_snapshot || var.aurora_final_snapshot_identifier != null
    error_message = "aurora_skip_final_snapshotをfalseにする場合は、aurora_final_snapshot_identifierを指定してください。"
  }

  validation {
    condition = var.aurora_final_snapshot_identifier == null ? true : (
      can(regex("^[A-Za-z][A-Za-z0-9-]{0,254}$", var.aurora_final_snapshot_identifier)) &&
      !strcontains(var.aurora_final_snapshot_identifier, "--") &&
      !endswith(var.aurora_final_snapshot_identifier, "-")
    )
    error_message = "aurora_final_snapshot_identifierは英字で始まる1〜255文字の英数字・ハイフンとし、末尾や連続したハイフンは使わないでください。"
  }
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
