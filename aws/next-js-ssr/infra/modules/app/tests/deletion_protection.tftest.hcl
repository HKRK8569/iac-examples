# planのみ・AWSプロバイダーはモック。実リソースの作成や削除は行わない。
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name_prefix          = "next-js-ssr-test"
  origin_verify_secret = "testOriginVerifySecret0123456789abcdef"
  vpc_id               = "vpc-0123456789abcdef0"
  public_subnet_ids    = ["subnet-00000000000000001", "subnet-00000000000000002"]
  app_subnet_ids       = ["subnet-00000000000000003", "subnet-00000000000000004"]
  db_subnet_ids        = ["subnet-00000000000000005", "subnet-00000000000000006"]
  db_name              = "app"
  db_username          = "postgres"
  db_password          = "testDatabasePassword"
  container_image      = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/test:fixture"
}

run "dev_defaults_remain_disposable" {
  command = plan

  assert {
    condition = (
      !aws_rds_cluster.this.deletion_protection &&
      !aws_lb.this.enable_deletion_protection &&
      aws_rds_cluster.this.skip_final_snapshot &&
      aws_rds_cluster.this.final_snapshot_identifier == null
    )
    error_message = "既存devのデフォルトは削除保護OFF・最終スナップショット省略のまま維持する必要があります。"
  }
}

run "production_protects_resources_and_preserves_snapshot" {
  command = plan

  variables {
    aurora_deletion_protection       = true
    alb_deletion_protection          = true
    aurora_skip_final_snapshot       = false
    aurora_final_snapshot_identifier = "next-js-ssr-prd-final-001"
  }

  assert {
    condition = (
      aws_rds_cluster.this.deletion_protection &&
      aws_lb.this.enable_deletion_protection &&
      !aws_rds_cluster.this.skip_final_snapshot &&
      aws_rds_cluster.this.final_snapshot_identifier == "next-js-ssr-prd-final-001"
    )
    error_message = "prd向け設定ではAurora・ALBを削除保護し、指定名で最終スナップショットを保存する必要があります。"
  }
}

run "aurora_protection_is_independent_of_alb" {
  command = plan
  variables {
    aurora_deletion_protection = true
  }
  assert {
    condition     = aws_rds_cluster.this.deletion_protection && !aws_lb.this.enable_deletion_protection
    error_message = "Auroraだけの削除保護を指定できる必要があります。"
  }
}

run "alb_protection_is_independent_of_aurora" {
  command = plan
  variables {
    alb_deletion_protection = true
  }
  assert {
    condition     = aws_lb.this.enable_deletion_protection && !aws_rds_cluster.this.deletion_protection
    error_message = "ALBだけの削除保護を指定できる必要があります。"
  }
}

run "disabling_protection_can_keep_snapshot_enabled" {
  command = plan
  variables {
    aurora_deletion_protection       = false
    alb_deletion_protection          = false
    aurora_skip_final_snapshot       = false
    aurora_final_snapshot_identifier = "next-js-ssr-prd-final-001"
  }
  assert {
    condition = (
      !aws_rds_cluster.this.deletion_protection &&
      !aws_lb.this.enable_deletion_protection &&
      !aws_rds_cluster.this.skip_final_snapshot &&
      aws_rds_cluster.this.final_snapshot_identifier == "next-js-ssr-prd-final-001"
    )
    error_message = "削除保護を解除するときも、最終スナップショットを保存する設定を独立して維持できる必要があります。"
  }
}

run "omit_snapshot_identifier_when_skipping" {
  command = plan
  variables {
    aurora_skip_final_snapshot       = true
    aurora_final_snapshot_identifier = "unused-final-snapshot"
  }
  assert {
    condition     = aws_rds_cluster.this.skip_final_snapshot && aws_rds_cluster.this.final_snapshot_identifier == null
    error_message = "最終スナップショットを省略する場合は、スナップショット名をAWSへ渡してはいけません。"
  }
}

run "reject_missing_snapshot_identifier" {
  command = plan
  variables {
    aurora_skip_final_snapshot = false
  }
  expect_failures = [var.aurora_final_snapshot_identifier]
}

run "reject_empty_snapshot_identifier" {
  command = plan
  variables {
    aurora_skip_final_snapshot       = false
    aurora_final_snapshot_identifier = ""
  }
  expect_failures = [var.aurora_final_snapshot_identifier]
}

run "reject_snapshot_identifier_starting_with_digit" {
  command = plan
  variables {
    aurora_skip_final_snapshot       = false
    aurora_final_snapshot_identifier = "1-invalid-snapshot"
  }
  expect_failures = [var.aurora_final_snapshot_identifier]
}

run "reject_snapshot_identifier_with_underscore" {
  command = plan
  variables {
    aurora_skip_final_snapshot       = false
    aurora_final_snapshot_identifier = "invalid_snapshot"
  }
  expect_failures = [var.aurora_final_snapshot_identifier]
}

run "reject_consecutive_hyphens" {
  command = plan
  variables {
    aurora_skip_final_snapshot       = false
    aurora_final_snapshot_identifier = "invalid--snapshot"
  }
  expect_failures = [var.aurora_final_snapshot_identifier]
}

run "reject_trailing_hyphen" {
  command = plan
  variables {
    aurora_skip_final_snapshot       = false
    aurora_final_snapshot_identifier = "invalid-snapshot-"
  }
  expect_failures = [var.aurora_final_snapshot_identifier]
}

run "reject_oversized_snapshot_identifier" {
  command = plan
  variables {
    aurora_skip_final_snapshot       = false
    aurora_final_snapshot_identifier = join("", [for i in range(256) : "a"])
  }
  expect_failures = [var.aurora_final_snapshot_identifier]
}

run "accept_single_letter_snapshot_identifier" {
  command = plan
  variables {
    aurora_skip_final_snapshot       = false
    aurora_final_snapshot_identifier = "a"
  }
  assert {
    condition     = aws_rds_cluster.this.final_snapshot_identifier == "a"
    error_message = "AWSの仕様で許可される1文字の英字は受け付ける必要があります。"
  }
}

run "accept_maximum_length_snapshot_identifier" {
  command = plan
  variables {
    aurora_skip_final_snapshot       = false
    aurora_final_snapshot_identifier = join("", [for i in range(255) : "a"])
  }
  assert {
    condition     = length(aws_rds_cluster.this.final_snapshot_identifier) == 255
    error_message = "AWSの仕様で許可される255文字の名前は受け付ける必要があります。"
  }
}
