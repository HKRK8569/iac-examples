# https://dev.classmethod.jp/articles/aws-resource-naming-rule-2024/
# VPCの設定
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-vpc"
    }
  )
}

# デフォルトセキュリティーグループの設定
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.this.id
  # デフォルトのセキュリティーグループの設定を閉じるように設定
  ingress = []
  egress  = []

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-default-sg"
    }
  )
}

# デフォルトNACLはIPv4の双方向通信を許可し、アクセス制限は各リソースのSGで行う
resource "aws_default_network_acl" "default" {
  default_network_acl_id = aws_vpc.this.default_network_acl_id

  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-default-nacl"
    }
  )
}

# デフォルトルートテーブルにタグ付け
resource "aws_default_route_table" "default" {
  default_route_table_id = aws_vpc.this.default_route_table_id

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-default-rt"
    }
  )
}
