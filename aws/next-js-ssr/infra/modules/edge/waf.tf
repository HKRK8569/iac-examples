locals {
  ip_allowlists = {
    ipv4 = {
      version  = "IPV4"
      priority = 0
      cidrs    = var.allowed_ipv4_cidrs
    }
    ipv6 = {
      version  = "IPV6"
      priority = 1
      cidrs    = var.allowed_ipv6_cidrs
    }
  }
}

# 一方が空でも両IPセットを維持し、CIDR変更時に参照中のIPセットを削除しない。
# 空のIPセットは一致しないため、そのIP種別の閲覧者はデフォルトアクションで拒否される。
resource "aws_wafv2_ip_set" "allowed" {
  provider = aws.us_east_1
  for_each = var.ip_restriction_enabled ? local.ip_allowlists : {}

  name               = "${var.name_prefix}-allowed-${each.key}"
  description        = "Allowed ${each.value.version} viewers for CloudFront"
  scope              = "CLOUDFRONT"
  ip_address_version = each.value.version
  addresses          = sort(distinct([for cidr in each.value.cidrs : cidrsubnet(cidr, 0, 0)]))

  tags = var.tags
}

resource "aws_wafv2_web_acl" "ip_restriction" {
  provider = aws.us_east_1
  count    = var.ip_restriction_enabled ? 1 : 0

  name        = "${var.name_prefix}-ip-restriction"
  description = "Allow only configured IPv4 and IPv6 viewers"
  scope       = "CLOUDFRONT"

  default_action {
    block {}
  }

  dynamic "rule" {
    for_each = aws_wafv2_ip_set.allowed

    content {
      name     = "allow-${rule.key}"
      priority = local.ip_allowlists[rule.key].priority

      action {
        allow {}
      }

      # X-Forwarded-Forではなく、CloudFrontが受け付けた接続元IPを判定する。
      statement {
        ip_set_reference_statement {
          arn = rule.value.arn
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-allow-${rule.key}"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-ip-restriction"
    sampled_requests_enabled   = true
  }

  tags = var.tags
}
