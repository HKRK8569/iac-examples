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
aws ssm start-session --target "$bastion" \
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

### CloudFrontからALBへのアクセス制限の確認

- [ ] 自分のCloudFront経由で `/api/health` が200になり、ページ・APIが利用できる
- [ ] ALBターゲットグループが正常で、秘密ヘッダー検証によってECSのヘルスチェックが失敗していない
- [ ] 検証用の別CloudFrontディストリビューションから同じALBへ転送した場合、秘密ヘッダーなし・誤った値の両方で `403 Access denied` になる
- [ ] 一般の端末からALBへ直接接続した場合は、引き続きSGで接続が遮断される

別CloudFrontでの確認には、ALBのDNS名をオリジンとする検証用ディストリビューションを使い、キャッシュを無効化してALBの応答を確認する。検証用には正しい秘密値を設定しない。オリジンへの接続プロトコルは実環境に合わせる（現構成ではHTTP）。検証後は検証用ディストリビューションを削除する。

端末からALBへの直接接続はSGで拒否されるため、403ではなく接続タイムアウトが想定される。ヘッダー検証による403の確認には、SGが許可するCloudFront経由の経路が必要。ヘルスチェック専用にヘッダー検証を回避するALBリスナールールは追加しない。

秘密値を再生成する場合は、ALBが旧値と新値の両方を受け付ける状態にしてからCloudFrontを切り替え、反映後に旧値を削除する。`terraform apply -replace=random_password.origin_verify` だけでのローテーションは、更新中の403を避けられない。

### 踏み台の自動停止の確認

削除してよいdevなどの検証環境で確認する。動作確認中は踏み台のSSM接続とDBトンネルが切断されるため、migrationなどの作業は終了しておく。

- [ ] 自動停止を有効にしてapplyし、Lambda・2つのEventBridgeルール・Schedulerグループが作成された
- [ ] 踏み台を停止してから再び起動し、専用Schedulerグループに `stop-<インスタンスID>-<起動時刻のUnix秒>` の単発予約が作成された。時刻が最新の起動時刻＋設定分数を基準にしている
- [ ] 設定分数の経過後に対象の踏み台だけが `stopping` / `stopped` になり、Lambdaログに `stop_requested` が記録された。実行済みの予約が自動削除された
- [ ] 期限前に手動で停止・起動し直した場合、新しい起動時刻から予約され、古い予約で早く停止されない
- [ ] 既存の起動中インスタンスや、停止時間の変更も、5分ごとの確認で最新の起動時刻を基準に反映される
- [ ] `bastion_auto_stop_enabled = false` をapplyすると自動停止用リソースとグループ内の予約が削除され、踏み台自体は維持される

検証時は停止時間を数分に短縮できるが、初回作成・予約欠落時の補完は5分間隔であり、Schedulerやイベント処理でも遅延する。検証後は希望する時間へ戻してapplyする。
失敗時はCloudWatch Logsの `/aws/lambda/<name_prefix>-bastion-auto-stop` とEventBridgeルールの配信失敗を確認する。自動停止は普段の停止操作の補助であり、接続の有無ではなく起動からの時間で判定する。

## 2回目以降の更新

コード変更時は手順4で新しいタグをpushし、`container_image` を更新して手順5の全体plan・applyを実行する。DBスキーマを変更する場合は、既存アプリと両立するmigrationを先に適用し、その後に新しいイメージへ切り替える。

### イメージ更新後のCloudFrontキャッシュ削除

一覧・投稿ページの静的シェルと `_next/static/*` は、CloudFrontで最大1時間キャッシュされる。新しいイメージには前のビルドのJS・CSSが含まれないため、古いシェルがエッジに残ると、参照先のアセットが404になり画面が崩れる可能性がある。イメージを切り替えたら、ECSの入れ替え完了を待ってからキャッシュを削除する。

Terraformの `apply` はECSサービスの入れ替え完了を待たない。入れ替え中にキャッシュを削除すると、旧タスクの応答が再びキャッシュされる可能性があるため、`services-stable` の完了後に実行する。

```bash
cdn="$(terraform -chdir=infra/env/dev output -raw cloudfront_domain_name)"
aws ecs wait services-stable --cluster next-js-ssr-dev-ecs-cluster --services next-js-ssr-dev-service --region ap-northeast-1
distribution_id="$(aws cloudfront list-distributions --query "DistributionList.Items[?DomainName=='${cdn}'].Id | [0]" --output text)"
aws cloudfront create-invalidation --distribution-id "$distribution_id" --paths '/*'
```

クラスター名・サービス名は `name_prefix = "next-js-ssr-dev"` の場合の値。変更していれば合わせる。`services-stable` は最大10分で待機を終了するため、タイムアウトした場合はECSサービスのイベントを確認してから再実行する。キャッシュ削除の完了は `aws cloudfront get-invalidation --distribution-id <ID> --id <Invalidation ID>` の `Status` が `Completed` になったことで確認する。`/*` の指定は1パスとして数えられ、月1,000パスまでは無料。

画像（`/images/*`）は毎回新しいキーで保存されるため、キャッシュ削除がなくても古い画像は表示されない。ブラウザ側では `_next/static/*` をファイル名のハッシュで区別するため、ブラウザキャッシュの削除は不要。

## 環境を削除するとき

削除保護が有効なリソースはAWS側で削除を拒否する。`terraform destroy` を先に実行すると、DBインスタンス・ECSなど保護対象外のリソースが削除されてから失敗する可能性がある。削除保護を、環境全体のdestroyを開始前に止める機能として扱わない。

1. 対象環境・backend・削除予定のリソースを確認する。最終スナップショットを残す場合は、`aurora_skip_final_snapshot = false` とし、既存スナップショットと重複しない名前を `aurora_final_snapshot_identifier` に設定する。
2. `aurora_deletion_protection` と `alb_deletion_protection` を `false` にする。スナップショットを保存する設定は変更しない。
3. 通常の `terraform plan` で意図した変更だけであることを確認し、`terraform apply` で削除保護の解除とスナップショット設定を反映する。tfvarsの編集やdestroy時の変数指定だけでは、AWS上の保護は解除されない。
4. AWS上でAuroraクラスターの `DeletionProtection` とALBの `deletion_protection.enabled` が無効になったことを確認する。
5. `terraform plan -destroy` で削除対象を確認し、対象環境を削除する。最終スナップショットを保存する設定なら、削除後に指定した名前のスナップショットが利用可能になっていることを確認する。

削除保護を有効にしたまま、動作確認だけのために本番環境のdestroyを実行しない。削除を伴う動作確認は、削除してよい検証環境で行う。
