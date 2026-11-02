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
}

variables {
  name_prefix                        = "next-js-ssr-test"
  origin_verify_secret               = "testOriginVerifySecret0123456789abcdef"
  alb_dns_name                       = "example.ap-northeast-1.elb.amazonaws.com"
  images_bucket_regional_domain_name = "next-js-ssr-test-images.s3.ap-northeast-1.amazonaws.com"
  images_bucket_id                   = "next-js-ssr-test-images"
  images_bucket_arn                  = "arn:aws:s3:::next-js-ssr-test-images"
}

run "attach_secret_only_to_alb_origin" {
  command = apply

  assert {
    condition = alltrue([
      for origin in aws_cloudfront_distribution.this.origin :
      origin.origin_id == "alb-origin" ? (
        length(origin.custom_header) == 1 &&
        one(origin.custom_header).name == "X-Origin-Verify" &&
        one(origin.custom_header).value == var.origin_verify_secret
      ) : length(origin.custom_header) == 0
    ]) && length(aws_cloudfront_distribution.this.origin) == 2
    error_message = "秘密ヘッダーはALBオリジンにだけ付与し、画像用S3オリジンへ送信してはいけません。"
  }

  assert {
    condition = (
      aws_cloudfront_distribution.this.default_cache_behavior[0].target_origin_id == "alb-origin" &&
      alltrue([
        for behavior in aws_cloudfront_distribution.this.ordered_cache_behavior :
        behavior.path_pattern == "/api/*" ? behavior.target_origin_id == "alb-origin" :
        behavior.path_pattern == "/images/*" && behavior.target_origin_id == "s3-images-origin"
      ])
    )
    error_message = "ページとAPIは検証対象のALBへ、画像はOACを使うS3オリジンへ転送する必要があります。"
  }
}

run "reject_empty_secret" {
  command = plan
  variables {
    origin_verify_secret = ""
  }
  expect_failures = [var.origin_verify_secret]
}

run "reject_short_secret" {
  command = plan
  variables {
    origin_verify_secret = "shortSecret"
  }
  expect_failures = [var.origin_verify_secret]
}

run "reject_wildcard_secret" {
  command = plan
  variables {
    origin_verify_secret = "testOriginVerifySecret0123456789*?"
  }
  expect_failures = [var.origin_verify_secret]
}

run "reject_whitespace_in_secret" {
  command = plan
  variables {
    origin_verify_secret = "testOriginVerifySecret0123456789 abcdef"
  }
  expect_failures = [var.origin_verify_secret]
}

run "reject_oversized_secret" {
  command = plan
  variables {
    origin_verify_secret = join("", [for i in range(129) : "a"])
  }
  expect_failures = [var.origin_verify_secret]
}
