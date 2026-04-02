terraform {
  required_version = ">= 1.5.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.14"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
# kvの設定
resource "cloudflare_workers_kv_namespace" "worker_kv" {
  account_id = var.account_id
  title      = "${var.script_name}-state"
}
# workersの設定
resource "cloudflare_worker" "worker" {
  account_id = var.account_id
  name       = var.script_name
}

resource "cloudflare_worker_version" "worker_version" {
  account_id = var.account_id
  worker_id  = cloudflare_worker.worker.id

  compatibility_date = var.compatibility_date
  main_module        = "worker.mjs"

  modules = [{
    name         = "worker.mjs"
    content_type = "application/javascript+module"
    content_file = var.worker_bundle_path
  }]

  # workersの環境変数
  bindings = [
    {
      type         = "kv_namespace"
      name         = "STATE_KV"
      namespace_id = cloudflare_workers_kv_namespace.worker_kv.id
    },
  ]
}


resource "cloudflare_workers_deployment" "worker_deployment" {
  account_id  = var.account_id
  script_name = cloudflare_worker.worker.name
  strategy    = "percentage"

  # 受信したリクエストの行先設定
  # 100%cloudflare_worker_version.workerに飛ばす
  versions = [{
    percentage = 100
    version_id = cloudflare_worker_version.worker_version.id
  }]
}

# 実行スケジュールの設定(UTC)
resource "cloudflare_workers_cron_trigger" "worker_cron_trigger" {
  account_id  = var.account_id
  script_name = cloudflare_worker.worker.name
  schedules = [
    for c in var.cron_schedules : {
      cron = c
    }
  ]
}
