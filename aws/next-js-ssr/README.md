# nextjs-ssr

## 概要
nextjs(SSR)をAWSにデプロイするterraformのコード
画像などはS3に配置しcloudFront経由で取得を行う想定
cloudfrontでSSRで生成したHTMLをキャッシュする

- app
   - nextjsのコードを配置
- infra
   - terraformのコードを配置

## ディレクトリ構成

```
infra/
├── env/                  # 環境ごとのルートモジュール（ここで terraform を実行する）
│   ├── dev/
│   ├── stg/
│   └── prd/
└── modules/              # 環境から呼び出される部品
    ├── network/          # VPC / subnet / IGW / NAT / route
    ├── app/              # ALB / ECS / Aurora / ECR / S3 / Secrets Manager
    └── edge/             # CloudFront
```

## デプロイ手順

AWSの認証情報を設定した上で、デプロイしたい環境のディレクトリで実行する。

```
cd infra/env/dev   # stg / prd の場合はディレクトリを変える
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集（DBパスワード・コンテナイメージ等）

terraform init
terraform plan
terraform apply
```

※ 同ディレクトリの `terraform.tfvars` は自動で読み込まれるため `-var-file` の指定は不要

## 削除方法

```
cd infra/env/dev
terraform destroy
```

## 構成図

![構成図](next-js-ssr-diagram.png)