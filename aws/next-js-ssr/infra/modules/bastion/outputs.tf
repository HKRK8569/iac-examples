output "instance_id" {
  value       = aws_instance.bastion.id
  description = "踏み台のインスタンスID（ssm start-session の --target に使用）"
}

output "security_group_id" {
  value       = aws_security_group.bastion.id
  description = "踏み台のSG ID（Aurora SGのingressに許可を追加するために使用）"
}
