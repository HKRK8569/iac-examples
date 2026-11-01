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

# CloudFrontの閲覧者IP制限
variable "ip_restriction_enabled" {
  description = "WAFで許可CIDR以外の閲覧者を拒否する。falseの場合はWAFを作成・関連付けしない"
  type        = bool
  default     = false
  nullable    = false

  validation {
    condition     = !var.ip_restriction_enabled || length(var.allowed_ipv4_cidrs) + length(var.allowed_ipv6_cidrs) > 0
    error_message = "IP制限を有効にする場合は、allowed_ipv4_cidrsまたはallowed_ipv6_cidrsに1件以上の許可CIDRを指定してください。"
  }
}

variable "allowed_ipv4_cidrs" {
  description = "許可するIPv4 CIDRの一覧（単一IPは/32）。/0はWAF非対応のため指定不可"
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for cidr in var.allowed_ipv4_cidrs :
      try(cidrnetmask(cidr) != "" && tonumber(split("/", cidr)[1]) > 0, false)
    ])
    error_message = "allowed_ipv4_cidrsには/1〜/32の有効なIPv4 CIDRを指定してください（例: 203.0.113.10/32）。"
  }
}

variable "allowed_ipv6_cidrs" {
  description = "許可するIPv6 CIDRの一覧（単一IPは/128）。/0はWAF非対応のため指定不可"
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for cidr in var.allowed_ipv6_cidrs :
      try(strcontains(cidrhost(cidr, 0), ":") && tonumber(split("/", cidr)[1]) > 0, false)
    ])
    error_message = "allowed_ipv6_cidrsには/1〜/128の有効なIPv6 CIDRを指定してください（例: 2001:db8::10/128）。"
  }
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
