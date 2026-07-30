# キャッシュ無効
data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# キャッシュ最適化
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# ssr用のキャッシュ設定
resource "aws_cloudfront_cache_policy" "ssr_cache" {
  name        = "${var.name_prefix}-ssr-cache"
  comment     = "SSRはデフォルトでキャッシュする"
  min_ttl     = 0
  default_ttl = 60
  max_ttl     = 3600

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Accept", "Host"]
      }
    }

    query_strings_config {
      query_string_behavior = "all"
    }

    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}

# 全て許可
data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

resource "aws_cloudfront_origin_request_policy" "ssr_public" {
  name    = "${var.name_prefix}-ssr-public"
  comment = "SSR用のリクエストポリシー"

  # cookieは送らない
  cookies_config {
    cookie_behavior = "none"
  }

  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["Accept", "Host"]
    }
  }

  # queryStringsは全て許可
  query_strings_config {
    query_string_behavior = "all"
  }
}
