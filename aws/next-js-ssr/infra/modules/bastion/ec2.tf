# Amazon Linux 2023 (arm64) の最新AMI
# SSMエージェントが標準搭載されている
data "aws_ami" "al2023_arm64" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-kernel-*-arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# 踏み台用SG
# 接続はSSM経由（エージェントからのアウトバウンド443）のみのため、インバウンドは一切開けない
resource "aws_security_group" "bastion" {
  name   = "${var.name_prefix}-bastion-sg"
  vpc_id = var.vpc_id

  egress {
    # アウトバウンドを全て許可する
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-bastion-sg"
  })
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.al2023_arm64.id
  instance_type = var.instance_type

  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.bastion.id]

  # SSM接続のみのため公開IP・SSHキーペアは持たせない
  associate_public_ip_address = false

  iam_instance_profile = aws_iam_instance_profile.bastion.name

  # IMDSv2を強制
  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-bastion"
  })
}
