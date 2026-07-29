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

# TODO: app追加時に alb_dns_name / ecr_repository_url / images_bucket_name を追加
# TODO: edge追加時に cloudfront_domain_name を追加
