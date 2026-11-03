# 共通
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

variable "subnet_id" {
  description = "踏み台を配置するサブネットID（appサブネット。SSM接続のためNATへの経路が必要）"
  type        = string
}

# ec2
variable "instance_type" {
  description = "踏み台のインスタンスタイプ。AMIがarm64のためGraviton系（t4g・m7g等）を指定する"
  type        = string
  default     = "t4g.nano"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]+[0-9]+g[a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_typeにはarm64のGraviton系インスタンスタイプを指定してください（例: t4g.nano、t4g.micro、m7g.medium）。"
  }
}

variable "auto_stop_enabled" {
  description = "踏み台の起動を検知し、指定時間後に自動停止する。無効化すると自動停止用リソースを削除する"
  type        = bool
  default     = false
  nullable    = false
}

variable "auto_stop_after_minutes" {
  description = "踏み台の起動から自動停止までの分数（1〜1440の整数）。SSM接続中でも停止する"
  type        = number
  default     = 60
  nullable    = false

  validation {
    condition = (
      var.auto_stop_after_minutes >= 1 && var.auto_stop_after_minutes <= 1440 &&
      floor(var.auto_stop_after_minutes) == var.auto_stop_after_minutes
    )
    error_message = "auto_stop_after_minutesには1〜1440の整数を指定してください。"
  }
}
