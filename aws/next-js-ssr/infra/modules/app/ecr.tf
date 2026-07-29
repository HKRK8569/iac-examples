
resource "aws_ecr_repository" "app" {
  name = "${var.name_prefix}-app"
  # 同じtag名は許可しない
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    # push時に脆弱性scanを行う
    scan_on_push = true
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-ecr-app"
  })
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "タグがついていないものは3日間で削除する"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 3
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "タグが付いているものは3つまで残す"
        selection = {
          tagStatus = "tagged"
          countType = "imageCountMoreThan"
          #   dev,prdなどで分ける場合多めにとる
          countNumber = 3
        }
        action = { type = "expire" }
      }
    ]
  })
}
