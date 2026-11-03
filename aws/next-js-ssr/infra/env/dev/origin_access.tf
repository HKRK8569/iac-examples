# 環境ごとに生成し、CloudFrontとALBへ同じ秘密値を渡す。
# 値はtfstateに保存される。再生成するときは両側の更新・CloudFrontの反映待ちが必要。
resource "random_password" "origin_verify" {
  length  = 64
  special = false
}
