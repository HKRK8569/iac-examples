resource "aws_s3_bucket" "images" {
  # バケット名はグローバル一意が必要なためアカウントIDをサフィックスに付ける
  bucket = "${var.name_prefix}-images-${data.aws_caller_identity.current.account_id}"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-bucket-images"
  })
}

resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id

  # publicにできないように設定
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
