# 共通
variable "multi_az" {
  description = "冗長化フラグ。falseにするとECSタスクを1つ・Auroraのreaderを0台に減らす（devコスト削減用）"
  type        = bool
  default     = true
}

variable "region" {
  description = "AWSリージョン（CloudWatch Logsの出力先指定に使用）"
  type        = string
  default     = "ap-northeast-1"
}

variable "tags" {
  description = "共通タグ"
  type        = map(string)
  default     = {}
}

variable "name_prefix" {
  description = "リソース命名のプレフィックス"
  type        = string
}

# CloudFrontからのオリジンアクセス検証
variable "origin_verify_secret" {
  description = "CloudFrontがX-Origin-Verifyヘッダーに付与する秘密値。edgeモジュールと同じ値を指定する"
  type        = string
  sensitive   = true
  nullable    = false

  validation {
    # ALBのヘッダー条件でワイルドカードとして解釈される * / ? も許可しない。
    condition     = can(regex("^[A-Za-z0-9]{32,128}$", var.origin_verify_secret))
    error_message = "origin_verify_secretには32〜128文字のランダムな半角英数字を指定してください。"
  }
}

# network（networkモジュールのoutputをルートから受け取る）
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "パブリックサブネットのID一覧（ALBを配置）"
  type        = list(string)
}

variable "app_subnet_ids" {
  description = "アプリ用プライベートサブネットのID一覧（ECSを配置）"
  type        = list(string)
}

variable "db_subnet_ids" {
  description = "DB用プライベートサブネットのID一覧（Auroraを配置）"
  type        = list(string)
}

# bastion
variable "bastion_security_group_id" {
  description = "踏み台のSG ID（指定するとAuroraへの5432を許可する。踏み台を置かない環境はnull）"
  type        = string
  default     = null
}

# 削除保護・最終スナップショット
variable "aurora_deletion_protection" {
  description = "Auroraクラスターの削除保護。prdではtrueにする。DBインスタンス自体の削除は防がない"
  type        = bool
  default     = false
  nullable    = false
}

variable "alb_deletion_protection" {
  description = "ALBの削除保護。prdではtrueにする"
  type        = bool
  default     = false
  nullable    = false
}

variable "aurora_skip_final_snapshot" {
  description = "Aurora削除時に最終スナップショットを省略する。prdではfalseにし、削除保護とは独立して設定する"
  type        = bool
  default     = true
  nullable    = false
}

variable "aurora_final_snapshot_identifier" {
  description = "Auroraの最終スナップショット名。保存する場合は必須。既存のスナップショットと重複しない名前を指定する"
  type        = string
  default     = null

  validation {
    condition     = var.aurora_skip_final_snapshot || var.aurora_final_snapshot_identifier != null
    error_message = "aurora_skip_final_snapshotをfalseにする場合は、aurora_final_snapshot_identifierを指定してください。"
  }

  validation {
    condition = var.aurora_final_snapshot_identifier == null ? true : (
      can(regex("^[A-Za-z][A-Za-z0-9-]{0,254}$", var.aurora_final_snapshot_identifier)) &&
      !strcontains(var.aurora_final_snapshot_identifier, "--") &&
      !endswith(var.aurora_final_snapshot_identifier, "-")
    )
    error_message = "aurora_final_snapshot_identifierは英字で始まる1〜255文字の英数字・ハイフンとし、末尾や連続したハイフンは使わないでください。"
  }
}

# aurora
variable "db_name" {
  description = "DB名"
  type        = string
}

variable "db_username" {
  description = "DBのユーザー名"
  type        = string
}

variable "db_password" {
  description = "DBのパスワード"
  type        = string
  sensitive   = true
}

variable "aurora_engine_version" {
  description = "Aurora PostgreSQLのバージョン（例: 17.6）。対象リージョンで新規作成できるバージョンを指定する"
  type        = string
  default     = "17.6"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.aurora_engine_version))
    error_message = "aurora_engine_versionは「メジャー.マイナー」形式で指定してください（例: 17.6）。"
  }
}

variable "aurora_instance_class" {
  description = "Auroraのwriter・readerのインスタンスクラス（例: db.t4g.medium）。Serverless v2は未対応"
  type        = string
  default     = "db.t4g.medium"
  nullable    = false

  validation {
    condition = (
      can(regex("^db\\.[a-z][a-z0-9-]*\\.[a-z0-9]+$", var.aurora_instance_class)) &&
      var.aurora_instance_class != "db.serverless"
    )
    error_message = "aurora_instance_classはdb.<ファミリー>.<サイズ>形式で指定してください（例: db.t4g.medium）。db.serverlessは未対応です。"
  }
}

# ecs
variable "container_port" {
  description = "ecsのポート"
  type        = number
  default     = 3000
}

variable "container_image" {
  description = "コンテナイメージ（ECRのURI:タグ）"
  type        = string
}

# Fargate（Linux / x86_64）で指定できるCPU・メモリの組み合わせ（MiB）
locals {
  fargate_memory_options = {
    256   = [512, 1024, 2048]
    512   = [for gb in range(1, 5) : gb * 1024]
    1024  = [for gb in range(2, 9) : gb * 1024]
    2048  = [for gb in range(4, 17) : gb * 1024]
    4096  = [for gb in range(8, 31) : gb * 1024]
    8192  = [for gb in range(16, 61, 4) : gb * 1024]
    16384 = [for gb in range(32, 121, 8) : gb * 1024]
  }
}

variable "ecs_task_cpu" {
  description = "ECSタスクのCPUユニット（1024 = 1 vCPU）。256 / 512 / 1024 / 2048 / 4096 / 8192 / 16384"
  type        = number
  default     = 256
  nullable    = false

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.ecs_task_cpu)
    error_message = "ecs_task_cpuは256 / 512 / 1024 / 2048 / 4096 / 8192 / 16384のいずれかを指定してください。"
  }
}

variable "ecs_task_memory" {
  description = "ECSタスクのメモリ（MiB）。ecs_task_cpuごとにFargateが許可する値を指定する"
  type        = number
  default     = 512
  nullable    = false

  validation {
    condition     = contains(lookup(local.fargate_memory_options, tostring(var.ecs_task_cpu), []), var.ecs_task_memory)
    error_message = "ecs_task_memoryはecs_task_cpuに対応する値を指定してください（例: 256→512/1024/2048、512→1024〜4096、1024→2048〜8192。いずれも1024刻み）。"
  }
}
