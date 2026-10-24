output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.this.domain_name
  description = "cloudFrontのデフォルトドメイン"
}

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.this.id
  description = "distribution ID（キャッシュのinvalidationに使用）"
}

output "cloudfront_distribution_arn" {
  value       = aws_cloudfront_distribution.this.arn
  description = "distribution ARN"
}
