# dev環境のデプロイ手順

Linux系のbashで、プロジェクトルート（`aws/next-js-ssr`）から実行する。現在ある環境定義は `infra/env/dev` のみ。初回はECRだけ先に作成し、イメージをpushしてから全体をapplyする。

## デプロイ前チェックリスト

- [ ] Terraform 1.10.0以上、AWS CLI、Session Manager plugin、Node.js/npmを入れ、Dockerが起動している
- [ ] `aws sts get-caller-identity` で対象アカウントを確認した（リソース作成ができる権限があること）
- [ ] 確認コマンドが一通り実行でき、確認コマンドの最後の2つで、Auroraのバージョンとインスタンスクラスが表示された（`None` ではない）

AWSアクセスキーを使う場合のみ、確認コマンドの前に以下を実行する（SSOやプロファイルを使う場合は不要）。環境変数はそのターミナルのセッション中だけ有効。キーをリポジトリ内のファイルに記載しない。

```bash
export AWS_ACCESS_KEY_ID='<アクセスキーID>'
export AWS_SECRET_ACCESS_KEY='<シークレットアクセスキー>'
export AWS_DEFAULT_REGION='ap-northeast-1'
# 一時的な認証情報の場合のみ
# export AWS_SESSION_TOKEN='<セッショントークン>'
```

確認コマンド:

```bash
terraform version
aws --version
session-manager-plugin --version
docker info --format '{{.ServerVersion}}'
node --version
aws sts get-caller-identity
aws rds describe-db-engine-versions --engine aurora-postgresql --engine-version 17.6 --region ap-northeast-1 --query 'DBEngineVersions[0].EngineVersion' --output text
aws rds describe-orderable-db-instance-options --engine aurora-postgresql --engine-version 17.6 --db-instance-class db.t4g.medium --region ap-northeast-1 --query 'OrderableDBInstanceOptions[0].DBInstanceClass' --output text
```

最後の2つは既定値（17.6・db.t4g.medium）の場合の例。`terraform.tfvars` の `aurora_engine_version` / `aurora_instance_class` を変更した場合はその値で確認する。`None` なら、そのリージョンで利用可能なバージョンとクラスを調べてtfvarsを調整する（[スペックの変更](README.md#ecsauroraのスペック)）。

## 1. tfstate用S3バケットを作る（初回のみ）

既に専用バケットがあれば作成を飛ばす。tfstateにはDBパスワードなどが含まれる。S3 backendのバケットはTerraformの管理外で先に作成する。

```bash
account_id="$(aws sts get-caller-identity --query Account --output text)"
state_bucket="next-js-ssr-tfstate-${account_id}"
aws s3api create-bucket --bucket "$state_bucket" --region ap-northeast-1 --create-bucket-configuration LocationConstraint=ap-northeast-1
aws s3api put-bucket-versioning --bucket "$state_bucket" --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$state_bucket" --public-access-block-configuration 'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
```

## 2. 変数とbackendを準備する（初回のみ）

既に `terraform.tfvars` と `dev.s3.tfbackend` がある場合はコピーせず再利用する。

```bash
cp infra/env/dev/terraform.tfvars.example infra/env/dev/terraform.tfvars
cp infra/env/dev/dev.s3.tfbackend.example infra/env/dev/dev.s3.tfbackend
```

`infra/env/dev/terraform.tfvars` の `db_password` を `CHANGE_ME` から実際の値に変更する。8〜128文字で、`/`・`"`・`@`・空白は使えない（Auroraの作成時にエラーになる）。`container_image` は手順4のpush後に設定するので、この時点ではプレースホルダーのままでよい。`infra/env/dev/dev.s3.tfbackend` の `<ACCOUNT_ID>` を対象アカウントIDに置き換える。

## 3. ECRだけ先に作る（初回のみ）

ECRがないとイメージをpushできず、イメージがないとECSタスクを起動できない。初回だけECRリポジトリに対象を絞って作成する。

```bash
terraform -chdir=infra/env/dev init -backend-config=dev.s3.tfbackend
terraform -chdir=infra/env/dev validate
terraform -chdir=infra/env/dev plan -target=module.app.aws_ecr_repository.app
terraform -chdir=infra/env/dev apply -target=module.app.aws_ecr_repository.app
```

## 4. DockerイメージをビルドしてECRへpushする

ECRはタグの上書きを禁止しているため、毎回新しいタグを使う。Dockerfileは `app/docker/Dockerfile`、ビルドコンテキストは `app`。

```bash
repo_uri="$(aws ecr describe-repositories --repository-names next-js-ssr-dev-app --region ap-northeast-1 --query 'repositories[0].repositoryUri' --output text)"
image_tag="$(git rev-parse --short HEAD)-$(date -u +%Y%m%d%H%M%S)"
image="${repo_uri}:${image_tag}"
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin "${repo_uri%%/*}"
docker build --platform linux/amd64 -f app/docker/Dockerfile -t "$image" app
docker push "$image"
printf '%s\n' "$image"
```

最後に表示されたイメージURIを、`infra/env/dev/terraform.tfvars` の `container_image` に設定する（例: 

`next-js-ssr-dev-app` は `name_prefix = "next-js-ssr-dev"` の場合の名前。変更していればリポジトリ名を合わせる。CloudFrontのデフォルトドメインは画像の相対URLで使うため、`NEXT_PUBLIC_CDN_DOMAIN` のビルド時指定は不要。

### うまくいかない場合（Docker Desktop + WSL）

`docker login` が `error storing credentials ... The stub received bad data.` で失敗する場合: Windowsの資格情報マネージャーにはECRのトークンが長すぎて保存できない。WSLの `~/.docker/config.json` から `credsStore` を削除して、ログインし直す（認証情報は `config.json` に保存される）。Docker Desktopは再起動時に `"credsStore": "desktop.exe"` を書き戻すため、再起動後に同じエラーが出たら再度実行する。

```bash
python3 -c 'import json,os;p=os.path.expanduser("~/.docker/config.json");d=json.load(open(p));d.pop("credsStore",None);json.dump(d,open(p,"w"),indent=2)'
```

## 5. 全体をapplyする

`infra/env/dev/terraform.tfvars` の `container_image` を、手順4で表示されたイメージURIに置き換える。planでイメージURIと作成対象を確認する。

```bash
terraform -chdir=infra/env/dev plan
terraform -chdir=infra/env/dev apply
terraform -chdir=infra/env/dev output
```

CloudFrontの作成と反映には時間がかかる。`IMAGES_BUCKET_NAME` は作成した画像バケット名からECSへ自動設定され、DB接続情報はSecrets Managerから注入される。`terraform.tfvars` は自動で読み込まれる。同じbackendなら2回目以降の `terraform init` に `-backend-config` の再指定は不要。

CloudFront→ALBの検証用秘密値もTerraformが生成し、両側へ同じ値を設定する。値はtfstate・AWS側の設定に保存されるため、アクセスを限定する。既存環境への初回導入では、ALBのデフォルト拒否とCloudFrontのヘッダー設定の反映時刻がずれると一時的に403になる可能性がある。CloudFrontが `Deployed` になってから手順7を確認する。

## 6. DB migrationを適用する

初回applyだけでは `reports` テーブルは作成されない。踏み台のSSMトンネル経由でmigrationを実行する。ターミナルAでトンネルを開いたまま、ターミナルBでmigrationを実行する。

ALBはDBに依存しない `/api/health` を確認するため、migration前でもタスクは正常になり得る。初回はCloudFront経由で `/api/health` が200、`/api/ready` が503であることを確認し、migration後に手順7で `/api/ready` の200を確認する。以下は新しいターミナルで実行する。

```bash
cdn="$(terraform -chdir=infra/env/dev output -raw cloudfront_domain_name)"
curl --fail --silent --show-error "https://${cdn}/api/health"
curl --silent --show-error --output /dev/null --write-out '%{http_code}' "https://${cdn}/api/ready"
```

この503はテーブル未作成による想定内の応答。ここでは `--fail` を付けず、出力が `503` であることを確認する。

ターミナルA:

```bash
writer="$(terraform -chdir=infra/env/dev output -raw aurora_writer_endpoint)"
bastion="$(terraform -chdir=infra/env/dev output -raw bastion_instance_id)"
aws ssm start-session --target "$bastion" --region ap-northeast-1 \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$writer\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"15432\"]}"
```

ターミナルB（プロジェクトルートから）:

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

## 環境を完全に削除する

プロジェクトルートからbashで順に実行する。DB・画像・イメージ・バックアップ・tfstateをすべて削除し、最終スナップショットも作成しない。SSM接続とDBトンネルを終了し、投稿・アップロード・イメージのpushを止めてから進める。

### 1. 削除用の設定を反映する

`region` と `name_prefix` は `infra/env/dev/terraform.tfvars` と同じ値にする。

```bash
region='ap-northeast-1'
name_prefix='next-js-ssr-dev'
terraform -chdir=infra/env/dev init -backend-config=dev.s3.tfbackend
```

`infra/env/dev/terraform.tfvars` を以下の設定にする。

```hcl
aurora_deletion_protection       = false
alb_deletion_protection          = false
aurora_skip_final_snapshot       = true
aurora_final_snapshot_identifier = null
```

削除保護の解除は、destroyより先に通常のapplyでAWSへ反映する。

```bash
terraform -chdir=infra/env/dev apply -auto-approve
```

### 2. アプリを停止する

ECSタスクを0にして停止を待つ。

```bash
aws ecs update-service --cluster "${name_prefix}-ecs-cluster" --service "${name_prefix}-service" --desired-count 0 --region "$region" --query 'service.desiredCount' --output text
aws ecs wait services-stable --cluster "${name_prefix}-ecs-cluster" --services "${name_prefix}-service" --region "$region"
```

### 3. S3・ECRのデータを削除する

画像をすべて削除する。

```bash
images_bucket="$(terraform -chdir=infra/env/dev output -raw images_bucket_name)"
aws s3 rm "s3://${images_bucket}/" --recursive --region "$region"
```

画像バケットで別途バージョニングを有効にした場合は、S3コンソールの「空にする」で過去バージョンと削除マーカーも削除する（[AWSのバケットを空にする手順](https://docs.aws.amazon.com/AmazonS3/latest/userguide/empty-bucket.html)）。

ECRリポジトリ `${name_prefix}-app` を、タグなしも含めたすべてのイメージごと削除する。buildxでpushしたマニフェストリストやattestationも残らない。

```bash
aws ecr delete-repository --repository-name "${name_prefix}-app" --force --region "$region"
```

ECRリポジトリは削除済みとして次のdestroyでstateから外れる。画像バケットは次のdestroyで削除する。

### 4. Terraform管理のリソースを削除する

```bash
terraform -chdir=infra/env/dev destroy -auto-approve
```

### 5. シークレットと既存のバックアップを完全に削除する

Terraformが削除予約したDBシークレットを、復旧期間なしで完全削除する（[AWSの完全削除手順](https://repost.aws/knowledge-center/delete-secrets-manager-secret)）。

```bash
aws secretsmanager delete-secret --secret-id "${name_prefix}-database-secret" --force-delete-without-recovery --region "$region"
```

シークレットの実際の削除はAWS側で非同期に処理される。

RDSコンソールの「スナップショット」から、この環境の `${name_prefix}-postgres` に属する既存の最終スナップショット・手動スナップショットをすべて削除する。保持済みの自動バックアップがあれば「自動バックアップ」の「保持」から削除する。別途保存したこの環境のDBダンプ・画像・ECRイメージのコピーも、保存先から削除する。

### 6. Terraform管理のリソースが残っていないことを確認し、tfstateを削除する

tfstate用S3バケットを削除する前に、Terraformの管理対象リソースが残っていないことを確認する。

```bash
terraform -chdir=infra/env/dev state list
```

正常終了して何も表示されなければ、tfstate上の管理対象リソースは残っていない。リソースが表示された場合は手順4のdestroyを再実行する。backendへの接続エラーは削除完了として扱わない。

確認後、`infra/env/dev/dev.s3.tfbackend` の `bucket` に記載したバケットをS3コンソールで選択し、「空にする」→「削除」の順に操作する。バージョニングが有効なため、過去のtfstate・削除マーカーも含めて削除する（[AWSのバケット削除手順](https://docs.aws.amazon.com/AmazonS3/latest/userguide/delete-bucket.html)）。

この手順はデプロイ手順1で作成した専用バケットを削除するもの。他環境と共有している場合は、この環境の `dev/` 配下の全バージョンと削除マーカーだけを削除し、共有バケット本体は残す。
