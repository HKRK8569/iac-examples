variable "cloudflare_api_token" {
  type    = string
  default = "apiToken"
}

variable "account_id" {
  type        = string
  description = "Cloudflare Account ID"
}

variable "script_name" {
  type        = string
  description = "Workers script name"
}

variable "compatibility_date" {
  type        = string
  description = "workerのランタイムの日付設定"
  default     = "2026-01-22"
}

variable "worker_bundle_path" {
  type        = string
  description = "ビルド済みWorkerファイルへのパス"
  default     = "dist/worker.mjs"
}

variable "cron_schedules" {
  type        = list(string)
  description = "cron"
  default     = ["*/30 * * * *"]
}

