# 画像バケットへのアクセスをこのdistribution経由のOACのみに限定する
# distributionのARNが必要なためバケット本体（app）ではなくedge側で定義している
resource "aws_s3_bucket_policy" "images" {
  bucket = var.images_bucket_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${var.images_bucket_arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.this.arn
          }
        }
      }
    ]
  })
}
