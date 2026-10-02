resource "aws_secretsmanager_secret" "database" {
  name = "${var.name_prefix}-database-secret"
}

resource "aws_secretsmanager_secret_version" "database" {
  secret_id = aws_secretsmanager_secret.database.id

  secret_string = jsonencode({
    db_name         = var.db_name
    username        = var.db_username
    password        = var.db_password
    writer_endpoint = aws_rds_cluster.this.endpoint
    reader_endpoint = aws_rds_cluster.this.reader_endpoint
    port            = aws_rds_cluster.this.port
  })
}
