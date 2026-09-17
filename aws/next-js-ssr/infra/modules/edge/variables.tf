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

# origin（appモジュールのoutputをルートから受け取る）
variable "alb_dns_name" {
  description = "オリジンにするALBのDNS名"
  type        = string
}

variable "images_bucket_regional_domain_name" {
  description = "画像用S3バケットのリージョナルドメイン名"
  type        = string
}

variable "images_bucket_id" {
  description = "画像用S3バケット名（バケットポリシーの設定先）"
  type        = string
}

variable "images_bucket_arn" {
  description = "画像用S3バケットARN（バケットポリシーで使用）"
  type        = string
}
