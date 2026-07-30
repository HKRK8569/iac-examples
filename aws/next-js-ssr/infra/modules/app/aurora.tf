
# auroraのサブネットの指定
resource "aws_db_subnet_group" "aurora" {
  name       = "${var.name_prefix}-aurora-subnet-group"
  subnet_ids = var.db_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-aurora-subnet-group"
  })
}

# auroraのSGの設定
resource "aws_security_group" "aurora" {
  name   = "${var.name_prefix}-aurora-sg"
  vpc_id = var.vpc_id

  ingress {
    # ECS（と踏み台がある環境では踏み台）からのみアクセスを許可する
    description = "Allow PostgreSQL from ECS and bastion"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = concat(
      [aws_security_group.app.id],
      var.bastion_security_group_id != null ? [var.bastion_security_group_id] : []
    )
  }

  egress {
    # アウトバウンドを全て許可する
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-aurora-sg"
  })
}


# auroraの定義
resource "aws_rds_cluster" "this" {
  cluster_identifier = "${var.name_prefix}-postgres"
  engine             = "aurora-postgresql"
  engine_version     = "17.6"
  database_name      = var.db_name
  master_username    = var.db_username
  master_password    = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.aurora.id]

  # バックアップの保持日数
  backup_retention_period = 7

  # サンプル用にdestroy時のスナップショット取得をスキップする
  # 本番運用ではfalseにすること
  skip_final_snapshot = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-postgres"
  })
}

# writerの設定
resource "aws_rds_cluster_instance" "writer" {
  identifier          = "${var.name_prefix}-postgres-writer"
  cluster_identifier  = aws_rds_cluster.this.id
  count               = 1
  instance_class      = "db.t4g.medium" # Aurora PostgreSQLの最小クラス（microは使用不可）
  engine              = aws_rds_cluster.this.engine
  engine_version      = aws_rds_cluster.this.engine_version
  publicly_accessible = false

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-postgres-writer"
    Role = "writer"
  })
}

# readerの設定
# 冗長化OFFのときは作らない（writerのみ）
resource "aws_rds_cluster_instance" "reader" {
  count               = var.multi_az ? 1 : 0
  identifier          = "${var.name_prefix}-postgres-reader-${count.index + 1}"
  cluster_identifier  = aws_rds_cluster.this.id
  instance_class      = "db.t4g.medium" # Aurora PostgreSQLの最小クラス（microは使用不可）
  engine              = aws_rds_cluster.this.engine
  engine_version      = aws_rds_cluster.this.engine_version
  publicly_accessible = false

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-postgres-reader-${count.index + 1}"
    Role = "reader"
  })
}

