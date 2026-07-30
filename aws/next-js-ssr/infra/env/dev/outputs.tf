# network
output "vpc_id" {
  value       = module.network.vpc_id
  description = "VPC ID"
}

output "public_subnet_ids" {
  value       = module.network.public_subnet_ids
  description = "パブリックサブネットID一覧"
}

output "app_subnet_ids" {
  value       = module.network.app_subnet_ids
  description = "アプリ用サブネットID一覧"
}

output "db_subnet_ids" {
  value       = module.network.db_subnet_ids
  description = "DB用サブネットID一覧"
}

# app
output "alb_dns_name" {
  value       = module.app.alb_dns_name
  description = "ALBのDNS名（CloudFront経由前の動作確認に使用）"
}

output "ecr_repository_url" {
  value       = module.app.ecr_repository_url
  description = "ECRリポジトリURL（docker pushに使用）"
}

output "images_bucket_name" {
  value       = module.app.images_bucket_name
  description = "画像用バケット名"
}

# edge
output "cloudfront_domain_name" {
  value       = module.edge.cloudfront_domain_name
  description = "cloudFrontのデフォルトドメイン（ここにアクセスして動作確認する）"
}
