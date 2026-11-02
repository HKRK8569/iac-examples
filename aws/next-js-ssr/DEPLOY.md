# dev環境のデプロイ手順

PowerShellまたはLinux系のbashで、プロジェクトルート（`aws/next-js-ssr`）から実行する。現在ある環境定義は `infra/env/dev` のみ。初回はECRだけ先に作成し、イメージをpushしてから全体をapplyする。

## デプロイ前チェックリスト

- [ ] Terraform 1.10.0以上、AWS CLI、Docker（Linuxコンテナ）、Node.js/npm、Session Manager pluginを用意し、Docker Engineを起動した
- [ ] `aws sts get-caller-identity` で対象アカウントを確認した。Terraformのリソース作成、ECR push、S3 backend、SSM接続の権限がある
- [ ] `ap-northeast-1` でAurora PostgreSQL `17.6` と `db.t4g.medium` が使えることを確認した。リージョン、AZ、VPC CIDR、継続的なAWS利用料金を確認した
- [ ] tfstate用S3バケットを用意し、バージョニングとパブリックアクセス遮断を設定した
- [ ] `terraform.tfvars` のDBパスワードを変更し、リソース名、サブネット、タグを確認した。`.tfvars`、`.tfbackend`、パスワードをGitに含めない
- [ ] 閲覧者を限定する場合は `cloudfront_ip_restriction_enabled = true` とし、`cloudfront_allowed_ipv4_cidrs` / `cloudfront_allowed_ipv6_cidrs` に実際の許可CIDRを設定した（複数指定可能。設定例は[README](README.md#cloudfrontの閲覧者ip制限)）。有効時はWAFを管理する `us-east-1` 側の権限も必要
- [ ] Dockerビルド環境からnpm、Google Fonts、RDSのCA証明書配布先へ接続できる
- [ ] CloudFront→ALBの秘密ヘッダー検証がplanに含まれ、ALBのデフォルト応答が403、秘密値一致時のみ転送になっている。秘密値は自動生成されるためtfvarsへの追記は不要。現構成はHTTP接続で、通信中の秘密値を保護するHTTPS化は別タスクであることを確認した
- [ ] 環境ごとのAurora・ALBの削除保護と最終スナップショットの設定を確認した。既定値はdev向け。prdでは両方の削除保護をtrue、`aurora_skip_final_snapshot`をfalseにし、一意な`aurora_final_snapshot_identifier`を指定する（[設定例](README.md#削除保護と最終スナップショット)）

AWSアクセスキーを使う場合は、以下を確認コマンドより前に実行する。環境変数はそのターミナルのセッション中だけ有効。手順6で別ターミナルを開く際も、そこでAWS CLIやTerraformを実行するなら同じ認証情報を設定する。キーをリポジトリ内のファイルに記載しない。

PowerShell:

```powershell
$env:AWS_ACCESS_KEY_ID = '<アクセスキーID>'
$env:AWS_SECRET_ACCESS_KEY = '<シークレットアクセスキー>'
$env:AWS_DEFAULT_REGION = 'ap-northeast-1'
# 一時的な認証情報の場合のみ
# $env:AWS_SESSION_TOKEN = '<セッショントークン>'
```

Linux系（bash）:

```bash
export AWS_ACCESS_KEY_ID='<アクセスキーID>'
export AWS_SECRET_ACCESS_KEY='<シークレットアクセスキー>'
export AWS_DEFAULT_REGION='ap-northeast-1'
# 一時的な認証情報の場合のみ
# export AWS_SESSION_TOKEN='<セッショントークン>'
```

確認コマンド（PowerShell・bash共通）:

```text
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

Linux系（bash）:

```bash
account_id="$(aws sts get-caller-identity --query Account --output text)"
state_bucket="next-js-ssr-tfstate-${account_id}"
aws s3api create-bucket --bucket "$state_bucket" --region ap-northeast-1 --create-bucket-configuration LocationConstraint=ap-northeast-1
aws s3api put-bucket-versioning --bucket "$state_bucket" --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$state_bucket" --public-access-block-configuration 'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
```

## 2. 変数とbackendを準備する（初回のみ）

既に `terraform.tfvars` と `dev.s3.tfbackend` がある場合はコピーせず再利用する。

```powershell
Copy-Item infra/env/dev/terraform.tfvars.example infra/env/dev/terraform.tfvars
Copy-Item infra/env/dev/dev.s3.tfbackend.example infra/env/dev/dev.s3.tfbackend
```

Linux系（bash）:

```bash
cp infra/env/dev/terraform.tfvars.example infra/env/dev/terraform.tfvars
cp infra/env/dev/dev.s3.tfbackend.example infra/env/dev/dev.s3.tfbackend
```

`infra/env/dev/terraform.tfvars` の `db_password` を実際の値にする。`container_image` は手順4のpush後に設定するので、この時点ではプレースホルダーのままでよい。`infra/env/dev/dev.s3.tfbackend` の `<ACCOUNT_ID>` を対象アカウントIDに置き換える。

## 3. ECRだけ先に作る（初回のみ）

ECRがないとイメージをpushできず、イメージがないとECSタスクを起動できない。初回だけECRリポジトリに対象を絞って作成する。

PowerShell・bash共通:

```text
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

Linux系（bash）:

```bash
repo_uri="$(aws ecr describe-repositories --repository-names next-js-ssr-dev-app --region ap-northeast-1 --query 'repositories[0].repositoryUri' --output text)"
registry="${repo_uri%%/*}"
image_tag="$(git rev-parse --short HEAD)-$(date -u +%Y%m%d%H%M%S)"
image="${repo_uri}:${image_tag}"
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin "$registry"
docker build --platform linux/amd64 -f app/docker/Dockerfile -t "$image" app
docker push "$image"
printf '%s\n' "$image"
```

`next-js-ssr-dev-app` は `name_prefix = "next-js-ssr-dev"` の場合の名前。変更していればリポジトリ名を合わせる。CloudFrontのデフォルトドメインは画像の相対URLで使うため、`NEXT_PUBLIC_CDN_DOMAIN` のビルド時指定は不要。

## 5. 全体をapplyする

`infra/env/dev/terraform.tfvars` の `container_image` を、手順4で表示されたイメージURIに置き換える。planでイメージURIと作成対象を確認する。

PowerShell・bash共通:

```text
terraform -chdir=infra/env/dev plan
terraform -chdir=infra/env/dev apply
terraform -chdir=infra/env/dev output
```

CloudFrontの作成と反映には時間がかかる。`IMAGES_BUCKET_NAME` は作成した画像バケット名からECSへ自動設定され、DB接続情報はSecrets Managerから注入される。`terraform.tfvars` は自動で読み込まれる。同じbackendなら2回目以降の `terraform init` に `-backend-config` の再指定は不要。

CloudFront→ALBの検証用秘密値もTerraformが生成し、両側へ同じ値を設定する。値はtfstate・AWS側の設定に保存されるため、アクセスを限定する。既存環境への初回導入では、ALBのデフォルト拒否とCloudFrontのヘッダー設定の反映時刻がずれると一時的に403になる可能性がある。CloudFrontが `Deployed` になってから手順7を確認する。

## 6. DB migrationを適用する

初回applyだけでは `reports` テーブルは作成されない。踏み台のSSMトンネル経由でmigrationを実行する。ターミナルAでトンネルを開いたまま、ターミナルBでmigrationを実行する。

ALBはDBに依存しない `/api/health` を確認するため、migration前でもタスクは正常になり得る。初回はCloudFront経由で `/api/health` が200、`/api/ready` が503であることを確認し、migration後に手順7で `/api/ready` の200を確認する。以下は新しいターミナルで実行する。

PowerShell:

```powershell
$cdn = terraform -chdir=infra/env/dev output -raw cloudfront_domain_name
Invoke-RestMethod "https://$cdn/api/health"
curl.exe --silent --show-error --output NUL --write-out '%{http_code}' "https://$cdn/api/ready"
```

Linux系（bash）:

```bash
cdn="$(terraform -chdir=infra/env/dev output -raw cloudfront_domain_name)"
curl --fail --silent --show-error "https://${cdn}/api/health"
curl --silent --show-error --output /dev/null --write-out '%{http_code}' "https://${cdn}/api/ready"
```

この503はテーブル未作成による想定内の応答。ここでは `--fail` を付けず、出力が `503` であることを確認する。

ターミナルA:

```powershell
$writer = terraform -chdir=infra/env/dev output -raw aurora_writer_endpoint
$bastion = terraform -chdir=infra/env/dev output -raw bastion_instance_id
aws ssm start-session --target $bastion --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters "host=$writer,portNumber=5432,localPortNumber=15432"
```

Linux系（bash）:

```bash
writer="$(terraform -chdir=infra/env/dev output -raw aurora_writer_endpoint)"
bastion="$(terraform -chdir=infra/env/dev output -raw bastion_instance_id)"
aws ssm start-session --target "$bastion" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$writer\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"15432\"]}"
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

Linux系（bash）:

```bash
mkdir -p app/certs
curl --fail --location --show-error https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o app/certs/global-bundle.pem
export DB_WRITER_ENDPOINT=127.0.0.1
export DB_SSL_SERVERNAME="$(terraform -chdir=infra/env/dev output -raw aurora_writer_endpoint)"
export DB_PORT=15432
export DB_SSL_MODE=verify-full
export DB_SSL_CA_PATH=./certs/global-bundle.pem
export DB_NAME=app
export DB_USERNAME=postgres
read -r -s -p 'Aurora DB password: ' DB_PASSWORD
printf '\n'
export DB_PASSWORD
cd app
npm run db:migrate
```

DB名・ユーザー名・パスワードは `terraform.tfvars` と同じ値にする。実行後はトンネルを終了し、DBパスワードを環境変数に残さないためターミナルBを閉じる。接続の詳細は [READMEのDB接続手順](README.md#dbへの接続踏み台経由) を参照する。

## 7. CloudFront経由で確認する

IP制限を有効にした場合は、許可した接続元から以下を実行する。IPv4・IPv6の両方を指定した場合は各経路で正常にアクセスできること、許可していない接続元からはページ・API・画像取得が403になることを確認する。`curl -4` / `curl -6` で使用するIP種別を指定できる（各ネットワークへの接続が必要）。`/api/health` と `/api/ready` もCloudFront経由ではWAFの対象になる。ALBからECSへのヘルスチェックはCloudFrontを通らない。

新しいターミナルをプロジェクトルートで開く。

```powershell
$cdn = terraform -chdir=infra/env/dev output -raw cloudfront_domain_name
Invoke-RestMethod "https://$cdn/api/health"
Invoke-RestMethod "https://$cdn/api/ready"
Invoke-WebRequest -UseBasicParsing "https://$cdn/"
Invoke-RestMethod "https://$cdn/api/reports?page=1"
```

Linux系（bash）:

```bash
cdn="$(terraform -chdir=infra/env/dev output -raw cloudfront_domain_name)"
curl --fail --location "https://${cdn}/api/health"
curl --fail --location "https://${cdn}/api/ready"
curl --fail --location "https://${cdn}/"
curl --fail --location "https://${cdn}/api/reports?page=1"
```

`/api/health` が200で `{"status":"ok"}`、`/api/ready` が200で `{"status":"ready"}` を返すことを確認する。`/api/ready` はwriter / reader両方のDB接続・`reports` テーブルの読み取りを確認し、接続失敗・テーブル未作成・タイムアウト時は503で `{"status":"not_ready"}` を返す。接続とクエリの待ち時間はそれぞれ2秒、確認用の接続は毎回閉じる。両APIはキャッシュしない。readinessは読み取りの確認なので、投稿や画像アップロードは以下で別途確認する。

一覧APIが200でJSONを返すことを確認する。`https://<CloudFrontドメイン>/reports/new` から画像付きの日報を投稿し、一覧と記事ページで画像が表示されることも確認する。失敗時はECSサービスのイベント、停止タスクの理由、CloudWatch Logsの `/ecs/next-js-ssr-dev` を調べる。

DBの準備状態は `/api/ready` で確認し、ALBの正常判定とは分けて扱う。CloudFrontの503エラーキャッシュもTTLを0に設定し、復旧後の確認で古い503を返さないようにする。DB障害でECSタスクの入れ替えを繰り返さないよう、ALBの確認先を `/api/ready` に変更しない。ローカルの `localhost:3000` からS3へ直接PUTするCORS設定もまだないので、画像投稿の確認はCloudFrontドメインから行う。

### CloudFrontからALBへのアクセス制限の確認

- [ ] 自分のCloudFront経由で `/api/health` が200になり、ページ・APIが利用できる
- [ ] ALBターゲットグループが正常で、秘密ヘッダー検証によってECSのヘルスチェックが失敗していない
- [ ] 検証用の別CloudFrontディストリビューションから同じALBへ転送した場合、秘密ヘッダーなし・誤った値の両方で `403 Access denied` になる
- [ ] 一般の端末からALBへ直接接続した場合は、引き続きSGで接続が遮断される

別CloudFrontでの確認には、ALBのDNS名をオリジンとする検証用ディストリビューションを使い、キャッシュを無効化してALBの応答を確認する。検証用には正しい秘密値を設定しない。オリジンへの接続プロトコルは実環境に合わせる（現構成ではHTTP）。検証後は検証用ディストリビューションを削除する。

端末からALBへの直接接続はSGで拒否されるため、403ではなく接続タイムアウトが想定される。ヘッダー検証による403の確認には、SGが許可するCloudFront経由の経路が必要。ヘルスチェック専用にヘッダー検証を回避するALBリスナールールは追加しない。

秘密値を再生成する場合は、ALBが旧値と新値の両方を受け付ける状態にしてからCloudFrontを切り替え、反映後に旧値を削除する。`terraform apply -replace=random_password.origin_verify` だけでのローテーションは、更新中の403を避けられない。

## 2回目以降の更新

コード変更時は手順4で新しいタグをpushし、`container_image` を更新して手順5の全体plan・applyを実行する。DBスキーマを変更する場合は、既存アプリと両立するmigrationを先に適用し、その後に新しいイメージへ切り替える。

## 環境を削除するとき

削除保護が有効なリソースはAWS側で削除を拒否する。`terraform destroy` を先に実行すると、DBインスタンス・ECSなど保護対象外のリソースが削除されてから失敗する可能性がある。削除保護を、環境全体のdestroyを開始前に止める機能として扱わない。

1. 対象環境・backend・削除予定のリソースを確認する。最終スナップショットを残す場合は、`aurora_skip_final_snapshot = false` とし、既存スナップショットと重複しない名前を `aurora_final_snapshot_identifier` に設定する。
2. `aurora_deletion_protection` と `alb_deletion_protection` を `false` にする。スナップショットを保存する設定は変更しない。
3. 通常の `terraform plan` で意図した変更だけであることを確認し、`terraform apply` で削除保護の解除とスナップショット設定を反映する。tfvarsの編集やdestroy時の変数指定だけでは、AWS上の保護は解除されない。
4. AWS上でAuroraクラスターの `DeletionProtection` とALBの `deletion_protection.enabled` が無効になったことを確認する。
5. `terraform plan -destroy` で削除対象を確認し、対象環境を削除する。最終スナップショットを保存する設定なら、削除後に指定した名前のスナップショットが利用可能になっていることを確認する。

削除保護を有効にしたまま、動作確認だけのために本番環境のdestroyを実行しない。削除を伴う動作確認は、削除してよい検証環境で行う。
