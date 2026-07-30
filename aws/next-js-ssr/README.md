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

### 0. tfstate用S3バケットの作成（初回のみ・任意）

tfstate（Terraformの状態ファイル）をS3で管理する場合は、専用バケットを事前に手動で作成する。
※ 個人での検証だけならローカル保存（デフォルト）のままでもよい。チーム開発・CI/CD導入前には必須。

```
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# バケット作成（tfstateはTerraform自身の管理外にするため手動で作る）
aws s3api create-bucket \
  --bucket next-js-ssr-tfstate-${ACCOUNT_ID} \
  --region ap-northeast-1 \
  --create-bucket-configuration LocationConstraint=ap-northeast-1

# バージョニング有効化（tfstateが壊れたとき過去の版に戻せるように）
aws s3api put-bucket-versioning \
  --bucket next-js-ssr-tfstate-${ACCOUNT_ID} \
  --versioning-configuration Status=Enabled

# パブリックアクセスの遮断（tfstateには機密情報が含まれる）
aws s3api put-public-access-block \
  --bucket next-js-ssr-tfstate-${ACCOUNT_ID} \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

バケット名は `main.tf` に直書きせず、`.tfbackend` ファイルに記載してinit時に渡す（手順1参照）。
ローカルにtfstateがある状態で切り替えると、S3への移行を促されるので `yes` で移行できる。

### 1. terraformの実行

AWSの認証情報を設定した上で、デプロイしたい環境のディレクトリで実行する。

```
cd infra/env/dev   # stg / prd の場合はディレクトリを変える

# 変数ファイルの準備
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集（DBパスワード・コンテナイメージ等）

# backend設定の準備（tfstateバケット名の指定）
cp dev.s3.tfbackend.example dev.s3.tfbackend
# dev.s3.tfbackend の <ACCOUNT_ID> を自分のアカウントIDに置き換える

terraform init -backend-config=dev.s3.tfbackend
terraform plan
terraform apply
```

※ `-backend-config` は初回initで `.terraform/` に記録されるため、2回目以降は `terraform init` だけでよい（バケットを変える場合は `-reconfigure` を付ける）

※ 同ディレクトリの `terraform.tfvars` は自動で読み込まれるため `-var-file` の指定は不要

## DBへの接続（踏み台経由）

Auroraはインターネット経路のないDBサブネットにあるため、踏み台EC2を経由した
SSMポートフォワーディングで接続する。踏み台はインバウンド全閉・公開IPなし・SSHキーなしで、
接続はSSM Session Manager（IAM認証）のみ。

### 前提

- AWS CLI + [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) をローカルにインストール
- 実行するIAMユーザー/ロールに `ssm:StartSession` の許可（対象を踏み台に限定する例）

```json
{
  "Effect": "Allow",
  "Action": "ssm:StartSession",
  "Resource": [
    "arn:aws:ec2:ap-northeast-1:<ACCOUNT_ID>:instance/<踏み台のインスタンスID>",
    "arn:aws:ssm:*:*:document/AWS-StartPortForwardingSessionToRemoteHost"
  ]
}
```

### 接続手順

```
cd infra/env/dev

# トンネルを張る（ローカルの15432 → Auroraの5432）
aws ssm start-session \
  --target $(terraform output -raw bastion_instance_id) \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$(terraform output -raw aurora_writer_endpoint)\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"15432\"]}"

# 別ターミナルから接続（パスワード等の接続情報はSecrets Managerに保存されている）
psql -h localhost -p 15432 -U postgres app
```

### DBの初期設定（初回のみ）

トンネルを張った状態で実行する。

```
# アプリ用のDBユーザーを作成する（master userをアプリから直接使わない）
psql -h localhost -p 15432 -U postgres app
app=> CREATE ROLE app_user WITH LOGIN PASSWORD '...';
app=> GRANT ALL ON SCHEMA public TO app_user;

# migrationの実行（アプリで採用するツールに合わせる。例: Prisma）
cd ../../../app
DATABASE_URL="postgresql://app_user:...@localhost:15432/app" npx prisma migrate deploy
```

### 踏み台の停止・起動

使わないときは停止しておく（EC2の課金を止める。SSM接続は起動中のみ可能）。

```
aws ec2 stop-instances --instance-ids $(terraform output -raw bastion_instance_id)
aws ec2 start-instances --instance-ids $(terraform output -raw bastion_instance_id)
```

## 削除方法

```
cd infra/env/dev
terraform destroy
```

## 構成図

![構成図](next-js-ssr-diagram.png)