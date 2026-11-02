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
  description = "踏み台のインスタンスタイプ"
  type        = string
  default     = "t4g.nano"
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
