output "images_bucket_name" {
  value       = aws_s3_bucket.images.bucket
  description = "画像用バケット名"
}

output "images_bucket_arn" {
  value       = aws_s3_bucket.images.arn
  description = "画像用バケットARN"
}

output "images_bucket_regional_domain_name" {
  value       = aws_s3_bucket.images.bucket_regional_domain_name
  description = "画像用バケットドメイン名"
}

output "alb_dns_name" {
  value       = aws_lb.this.dns_name
  description = "ALBのDNS名（CloudFrontのオリジンに使用）"
}

output "ecr_repository_url" {
  value       = aws_ecr_repository.app.repository_url
  description = "ECRリポジトリURL（docker pushに使用）"
}

output "aurora_writer_endpoint" {
  value       = aws_rds_cluster.this.endpoint
  description = "Auroraのwriterエンドポイント（踏み台経由の接続・migrationに使用）"
}
