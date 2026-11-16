# cloudFlareWorkerTemplate

## 概要

TypeScriptのWorkerをビルドし、TerraformでCloudflare Workers・KV・Cronを作成するテンプレートです。

HTTPアクセスとCron実行で、共通のKVキー `invocation_count` を1ずつ増やします。初回は `1` を保存し、HTTPでは `Hello World! invocation_count=1` のように返します。

KVの更新はアトミックではないため、同時実行などで加算を取りこぼす場合があります。動作確認用のカウンターです。

## 前提

- Node.js・npm
- Terraform 1.5.0以上
- デプロイ先のCloudflareアカウントとAccount ID
- 対象アカウントの `Workers Scripts: Edit` と `Workers KV Storage: Edit` 権限を持つAPIトークン

## デプロイ手順

以下は、このREADMEがある `cloudFlare/cloudFlareWorkerTemplate` ディレクトリから実行します。

### 1. Terraform変数を設定する

`terraform/terraform.tfvars` がまだない場合は、サンプルをコピーします。既存ファイルがある場合はそのまま編集してください。

```bash
cp -n terraform/terraform.tfvars.example terraform/terraform.tfvars
```

`terraform/terraform.tfvars` を編集します。

```hcl
cloudflare_api_token = "発行したAPIトークン"
account_id           = "デプロイ先のAccount ID"
script_name          = "worker"
compatibility_date   = "2026-01-22"
worker_bundle_path   = "../app/dist/worker.mjs"
cron_schedules       = ["*/30 * * * *"]
workers_subdomain    = "YOUR_SUBDOMAIN"
allowed_ip_ranges    = ["203.0.113.10/32", "198.51.100.20/32"]
```

- APIトークンはCloudflareのAPI Tokens画面で作成します。
- サンプルの `YYYY-MM-DD` は、上記のような有効な日付に置き換えてください。
- CronのタイムゾーンはUTCです。上記は毎時0分・30分に実行します。
- APIトークンを含む `terraform.tfvars` はGitにコミットしないでください。

### 2. Workerをビルド

```bash
cd app
npm ci
npx tsc --noEmit
npm run build
cd ..
```

`app/dist/worker.mjs` が生成されます。Workerのコード変更後も、デプロイ前に必ず再ビルドしてください。

### 3. Terraformを初期化・検証

```bash
cd terraform
terraform init
terraform validate
terraform plan
```

### 4. デプロイ

```bash
terraform apply
```


Terraformのstateは既定でローカルに保存されます。次回の更新にも必要なため、安全に保管し、Gitにはコミットしないでください。

## 動作確認

```bash
curl https://<公開したWorkerのホスト名>/
```

レスポンス例：`Hello World! invocation_count=2`

## 削除手順

デプロイ時のstateと `terraform.tfvars` を使用します。このREADMEがあるディレクトリから実行してください。

```bash
cd terraform
terraform plan -destroy
terraform destroy
```