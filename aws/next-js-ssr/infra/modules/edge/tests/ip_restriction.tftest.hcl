# 全AWSプロバイダーをモックし、AWS接続・リソース作成なしで検証する。
mock_provider "aws" {
  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn         = "arn:aws:cloudfront::123456789012:distribution/TEST"
      domain_name = "d111111abcdef8.cloudfront.net"
    }
  }
}

mock_provider "aws" {
  alias = "us_east_1"

  mock_resource "aws_wafv2_ip_set" {
    defaults = {
      arn = "arn:aws:wafv2:us-east-1:123456789012:global/ipset/test/11111111-1111-1111-1111-111111111111"
    }
  }

  mock_resource "aws_wafv2_web_acl" {
    defaults = {
      arn = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/test/22222222-2222-2222-2222-222222222222"
    }
  }
}

variables {
  name_prefix                        = "next-js-ssr-test"
  alb_dns_name                       = "example.ap-northeast-1.elb.amazonaws.com"
  images_bucket_regional_domain_name = "next-js-ssr-test-images.s3.ap-northeast-1.amazonaws.com"
  images_bucket_id                   = "next-js-ssr-test-images"
  images_bucket_arn                  = "arn:aws:s3:::next-js-ssr-test-images"
}

run "disabled_by_default" {
  command = apply

  assert {
    condition     = length(aws_wafv2_web_acl.ip_restriction) == 0 && length(aws_wafv2_ip_set.allowed) == 0
    error_message = "IP制限が無効ならWAFリソースを作成してはいけません。"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.web_acl_id == null
    error_message = "IP制限が無効ならCloudFrontにWeb ACLを関連付けてはいけません。"
  }
}

run "multiple_ipv4_only" {
  command = apply

  variables {
    ip_restriction_enabled = true
    allowed_ipv4_cidrs     = ["203.0.113.10/32", "198.51.100.25/24", "203.0.113.10/32"]
  }

  assert {
    condition     = toset(aws_wafv2_ip_set.allowed["ipv4"].addresses) == toset(["203.0.113.10/32", "198.51.100.0/24"])
    error_message = "複数IPv4 CIDRを正規化・重複除去して設定する必要があります。"
  }

  assert {
    condition     = aws_wafv2_ip_set.allowed["ipv4"].ip_address_version == "IPV4" && length(aws_wafv2_ip_set.allowed["ipv6"].addresses) == 0
    error_message = "IPv4だけの指定ではIPv6 IPセットを空にし、IPv6を許可してはいけません。"
  }
}

run "multiple_ipv6_only" {
  command = apply

  variables {
    ip_restriction_enabled = true
    allowed_ipv6_cidrs     = ["2001:db8::10/128", "2001:db8:1234::1/48"]
  }

  assert {
    condition     = toset(aws_wafv2_ip_set.allowed["ipv6"].addresses) == toset(["2001:db8::10/128", "2001:db8:1234::/48"])
    error_message = "複数IPv6 CIDRを正規化して設定する必要があります。"
  }

  assert {
    condition     = aws_wafv2_ip_set.allowed["ipv6"].ip_address_version == "IPV6" && length(aws_wafv2_ip_set.allowed["ipv4"].addresses) == 0
    error_message = "IPv6だけの指定ではIPv4 IPセットを空にし、IPv4を許可してはいけません。"
  }
}

run "both_families_allow_only_configured_networks" {
  command = apply

  variables {
    ip_restriction_enabled = true
    allowed_ipv4_cidrs     = ["203.0.113.10/32", "198.51.100.0/24"]
    allowed_ipv6_cidrs     = ["2001:db8::10/128", "2001:db8:1234::/48"]
  }

  assert {
    condition     = length(aws_wafv2_ip_set.allowed) == 2 && length(aws_wafv2_web_acl.ip_restriction[0].rule) == 2
    error_message = "IPv4・IPv6それぞれのIPセットと許可ルールが必要です。"
  }

  assert {
    condition = alltrue([
      for rule in aws_wafv2_web_acl.ip_restriction[0].rule :
      length(rule.action[0].allow) == 1 &&
      rule.statement[0].ip_set_reference_statement[0].arn == aws_wafv2_ip_set.allowed[trimprefix(rule.name, "allow-")].arn &&
      length(rule.statement[0].ip_set_reference_statement[0].ip_set_forwarded_ip_config) == 0
    ])
    error_message = "許可ルールは対応するIPセットで接続元IPを確認する必要があります。"
  }

  assert {
    condition     = length(aws_wafv2_web_acl.ip_restriction[0].default_action[0].block) == 1
    error_message = "許可IPに一致しないリクエストはデフォルトで拒否する必要があります。"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.web_acl_id == aws_wafv2_web_acl.ip_restriction[0].arn && aws_cloudfront_distribution.this.is_ipv6_enabled
    error_message = "Web ACLをCloudFrontに関連付け、IPv6の受付も維持する必要があります。"
  }

  assert {
    condition     = aws_wafv2_web_acl.ip_restriction[0].scope == "CLOUDFRONT" && alltrue([for ip_set in aws_wafv2_ip_set.allowed : ip_set.scope == "CLOUDFRONT"])
    error_message = "Web ACLと両IPセットはCLOUDFRONTスコープでなければなりません。"
  }
}

run "reject_empty_allowlists" {
  command = plan

  variables {
    ip_restriction_enabled = true
  }

  expect_failures = [var.ip_restriction_enabled]
}

run "reject_ipv4_without_prefix" {
  command = plan

  variables {
    ip_restriction_enabled = true
    allowed_ipv4_cidrs     = ["203.0.113.10"]
  }

  expect_failures = [var.allowed_ipv4_cidrs]
}

run "reject_invalid_ipv4_address" {
  command = plan

  variables {
    ip_restriction_enabled = true
    allowed_ipv4_cidrs     = ["999.0.0.1/32"]
  }

  expect_failures = [var.allowed_ipv4_cidrs]
}

run "reject_ipv6_in_ipv4_list" {
  command = plan

  variables {
    ip_restriction_enabled = true
    allowed_ipv4_cidrs     = ["2001:db8::1/128"]
  }

  expect_failures = [var.allowed_ipv4_cidrs]
}

run "reject_ipv4_in_ipv6_list" {
  command = plan

  variables {
    ip_restriction_enabled = true
    allowed_ipv6_cidrs     = ["203.0.113.10/32"]
  }

  expect_failures = [var.allowed_ipv6_cidrs]
}

run "reject_invalid_ipv6_prefix" {
  command = plan

  variables {
    ip_restriction_enabled = true
    allowed_ipv6_cidrs     = ["2001:db8::/129"]
  }

  expect_failures = [var.allowed_ipv6_cidrs]
}

run "reject_ipv4_default_route" {
  command = plan

  variables {
    ip_restriction_enabled = true
    allowed_ipv4_cidrs     = ["0.0.0.0/0"]
  }

  expect_failures = [var.allowed_ipv4_cidrs]
}

run "reject_ipv6_default_route" {
  command = plan

  variables {
    ip_restriction_enabled = true
    allowed_ipv6_cidrs     = ["::/0"]
  }

  expect_failures = [var.allowed_ipv6_cidrs]
}

run "disable_with_existing_allowlists" {
  command = apply

  variables {
    ip_restriction_enabled = false
    allowed_ipv4_cidrs     = ["203.0.113.10/32"]
    allowed_ipv6_cidrs     = ["2001:db8::10/128"]
  }

  assert {
    condition     = length(aws_wafv2_web_acl.ip_restriction) == 0 && length(aws_wafv2_ip_set.allowed) == 0 && aws_cloudfront_distribution.this.web_acl_id == null
    error_message = "無効に切り替えた場合は、CIDRが残っていてもWAFと関連付けを除去する必要があります。"
  }
}
