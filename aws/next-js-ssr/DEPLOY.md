# dev環境のデプロイ手順

PowerShellでプロジェクトルートから実行する。現在ある環境定義は `infra/env/dev` のみ。初回はECRだけ先に作成し、イメージをpushしてから全体をapplyする。

## デプロイ前チェックリスト

- [ ] Terraform 1.10.0以上、AWS CLI、Docker（Linuxコンテナ）、Node.js/npm、Session Manager pluginを用意し、Docker Engineを起動した
- [ ] `aws sts get-caller-identity` で対象アカウントを確認した。Terraformのリソース作成、ECR push、S3 backend、SSM接続の権限がある
- [ ] `ap-northeast-1` でAurora PostgreSQL `17.6` と `db.t4g.medium` が使えることを確認した。リージョン、AZ、VPC CIDR、継続的なAWS利用料金を確認した
- [ ] tfstate用S3バケットを用意し、バージョニングとパブリックアクセス遮断を設定した
- [ ] `terraform.tfvars` のDBパスワードを変更し、リソース名、サブネット、タグを確認した。`.tfvars`、`.tfbackend`、パスワードをGitに含めない
- [ ] Dockerビルド環境からnpm、Google Fonts、RDSのCA証明書配布先へ接続できる

確認コマンド:

```powershell
terraform version
aws --version
docker info --format '{{.ServerVersion}}'
node --version
aws sts get-caller-identity
aws rds describe-db-engine-versions --engine aurora-postgresql --engine-version 17.6 --region ap-northeast-1 --query 'DBEngineVersions[0].EngineVersion' --output text
aws rds describe-orderable-db-instance-options --engine aurora-postgresql --engine-version 17.6 --db-instance-class db.t4g.medium --region ap-northeast-1 --query 'OrderableDBInstanceOptions[0].DBInstanceClass' --output text
```

最後の2つが `None` なら、そのリージョンで利用可能なバージョンとクラスを調べてTerraformの設定を調整する。

## 1. tfstate用S3バケットを作る（初回のみ）

既に専用バケットがあれば作成を飛ばす。tfstateにはDBパスワードなどが含まれる。S3 backendのバケットはTerraformの管理外で先に作成する。

```powershell
$accountId = aws sts get-caller-identity --query Account --output text
$stateBucket = "next-js-ssr-tfstate-$accountId"
aws s3api create-bucket --bucket $stateBucket --region ap-northeast-1 --create-bucket-configuration LocationConstraint=ap-northeast-1
aws s3api put-bucket-versioning --bucket $stateBucket --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket $stateBucket --public-access-block-configuration 'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
```

## 2. 変数とbackendを準備する（初回のみ）

既に `terraform.tfvars` と `dev.s3.tfbackend` がある場合はコピーせず再利用する。

```powershell
Copy-Item infra/env/dev/terraform.tfvars.example infra/env/dev/terraform.tfvars
Copy-Item infra/env/dev/dev.s3.tfbackend.example infra/env/dev/dev.s3.tfbackend
```

`infra/env/dev/terraform.tfvars` の `db_password` を実際の値にする。`container_image` は手順4のpush後に設定するので、この時点ではプレースホルダーのままでよい。`infra/env/dev/dev.s3.tfbackend` の `<ACCOUNT_ID>` を対象アカウントIDに置き換える。

## 3. ECRだけ先に作る（初回のみ）

ECRがないとイメージをpushできず、イメージがないとECSタスクを起動できない。初回だけECRリポジトリに対象を絞って作成する。

```powershell
terraform -chdir=infra/env/dev init -backend-config=dev.s3.tfbackend
terraform -chdir=infra/env/dev validate
terraform -chdir=infra/env/dev plan -target=module.app.aws_ecr_repository.app
terraform -chdir=infra/env/dev apply -target=module.app.aws_ecr_repository.app
```

`-target` は初回の作成順序を解決するためだけに使う。その後は必ず全体のplan・applyを実行する。既存のtfstateをS3へ移行する場合は、`init` が提示する移行内容を確認する。

## 4. DockerイメージをビルドしてECRへpushする

ECRはタグの上書きを禁止しているため、毎回新しいタグを使う。Dockerfileは `app/docker/Dockerfile`、ビルドコンテキストは `app`。

```powershell
$repoUri = aws ecr describe-repositories --repository-names next-js-ssr-dev-app --region ap-northeast-1 --query 'repositories[0].repositoryUri' --output text
$registry = $repoUri.Split('/')[0]
$imageTag = "$(git rev-parse --short HEAD)-$(Get-Date -Format 'yyyyMMddHHmmss')"
$image = "${repoUri}:${imageTag}"
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin $registry
docker build --platform linux/amd64 -f app/docker/Dockerfile -t $image app
docker push $image
$image
```

`next-js-ssr-dev-app` は `name_prefix = "next-js-ssr-dev"` の場合の名前。変更していればリポジトリ名を合わせる。CloudFrontのデフォルトドメインは画像の相対URLで使うため、`NEXT_PUBLIC_CDN_DOMAIN` のビルド時指定は不要。

## 5. 全体をapplyする

`infra/env/dev/terraform.tfvars` の `container_image` を、手順4で表示された `$image` のURIに置き換える。planでイメージURIと作成対象を確認する。

```powershell
terraform -chdir=infra/env/dev plan
terraform -chdir=infra/env/dev apply
terraform -chdir=infra/env/dev output
```

CloudFrontの作成と反映には時間がかかる。`IMAGES_BUCKET_NAME` は作成した画像バケット名からECSへ自動設定され、DB接続情報はSecrets Managerから注入される。`terraform.tfvars` は自動で読み込まれる。同じbackendなら2回目以降の `terraform init` に `-backend-config` の再指定は不要。

## 6. DB migrationを適用する

初回applyだけでは `reports` テーブルは作成されない。踏み台のSSMトンネル経由でmigrationを実行する。ターミナルAでトンネルを開いたまま、ターミナルBでmigrationを実行する。

ターミナルA:

```powershell
$writer = terraform -chdir=infra/env/dev output -raw aurora_writer_endpoint
$bastion = terraform -chdir=infra/env/dev output -raw bastion_instance_id
aws ssm start-session --target $bastion --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters "host=$writer,portNumber=5432,localPortNumber=15432"
```

ターミナルB（プロジェクトルートから）:

```powershell
New-Item -ItemType Directory -Force app/certs | Out-Null
Invoke-WebRequest -Uri https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -OutFile app/certs/global-bundle.pem
$env:DB_WRITER_ENDPOINT = '127.0.0.1'
$env:DB_SSL_SERVERNAME = terraform -chdir=infra/env/dev output -raw aurora_writer_endpoint
$env:DB_PORT = '15432'
$env:DB_SSL_MODE = 'verify-full'
$env:DB_SSL_CA_PATH = './certs/global-bundle.pem'
$env:DB_NAME = 'app'
$env:DB_USERNAME = 'postgres'
$securePassword = Read-Host 'Aurora DB password' -AsSecureString
$env:DB_PASSWORD = [System.Net.NetworkCredential]::new('', $securePassword).Password
Set-Location app
npm.cmd run db:migrate
```

DB名・ユーザー名・パスワードは `terraform.tfvars` と同じ値にする。実行後はトンネルを終了し、DBパスワードを環境変数に残さないためターミナルBを閉じる。接続の詳細は [READMEのDB接続手順](README.md#dbへの接続踏み台経由) を参照する。

## 7. CloudFront経由で確認する

新しいターミナルをプロジェクトルートで開く。

```powershell
$cdn = terraform -chdir=infra/env/dev output -raw cloudfront_domain_name
Invoke-WebRequest -UseBasicParsing "https://$cdn/"
Invoke-RestMethod "https://$cdn/api/reports?page=1"
```

一覧APIが200でJSONを返すことを確認する。`https://<CloudFrontドメイン>/reports/new` から画像付きの日報を投稿し、一覧と記事ページで画像が表示されることも確認する。失敗時はECSサービスのイベント、停止タスクの理由、CloudWatch Logsの `/ecs/next-js-ssr-dev` を調べる。

現状のALBヘルスチェックは静的な `/` を見るため、タスクが正常表示でもDB処理は確認できない。ローカルの `localhost:3000` からS3へ直接PUTするCORS設定もまだないので、画像投稿の確認はCloudFrontドメインから行う。

## 2回目以降の更新

コード変更時は手順4で新しいタグをpushし、`container_image` を更新して手順5の全体plan・applyを実行する。DBスキーマを変更する場合は、既存アプリと両立するmigrationを先に適用し、その後に新しいイメージへ切り替える。
