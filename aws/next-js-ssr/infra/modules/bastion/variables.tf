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
