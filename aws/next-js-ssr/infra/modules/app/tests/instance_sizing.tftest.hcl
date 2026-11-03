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

run "defaults_keep_existing_specs" {
  command = plan

  assert {
    condition = (
      aws_ecs_task_definition.this.cpu == "256" &&
      aws_ecs_task_definition.this.memory == "512" &&
      aws_rds_cluster.this.engine_version == "17.6" &&
      aws_rds_cluster_instance.writer[0].instance_class == "db.t4g.medium" &&
      !aws_rds_cluster_instance.writer[0].auto_minor_version_upgrade
    )
    error_message = "既定値は変数化前と同じECS 256/512・Aurora 17.6・db.t4g.mediumである必要があります。"
  }
}

run "custom_specs_apply_to_writer_and_reader" {
  command = plan

  variables {
    multi_az              = true
    ecs_task_cpu          = 1024
    ecs_task_memory       = 2048
    aurora_engine_version = "17.7"
    aurora_instance_class = "db.r7g.large"
  }

  assert {
    condition = (
      aws_ecs_task_definition.this.cpu == "1024" &&
      aws_ecs_task_definition.this.memory == "2048" &&
      aws_rds_cluster.this.engine_version == "17.7" &&
      aws_rds_cluster_instance.writer[0].instance_class == "db.r7g.large" &&
      aws_rds_cluster_instance.reader[0].instance_class == "db.r7g.large" &&
      !aws_rds_cluster_instance.reader[0].auto_minor_version_upgrade
    )
    error_message = "指定したECS・Auroraのスペックがタスク定義とwriter・readerに反映される必要があります。"
  }
}

run "accept_large_cpu_memory_step" {
  command = plan

  variables {
    ecs_task_cpu    = 8192
    ecs_task_memory = 20480
  }

  assert {
    condition     = aws_ecs_task_definition.this.memory == "20480"
    error_message = "8 vCPUでは4GiB刻みのメモリを許可する必要があります。"
  }
}

run "reject_unsupported_cpu" {
  command = plan
  variables {
    ecs_task_cpu = 300
  }
  expect_failures = [var.ecs_task_cpu]
}

run "reject_memory_not_allowed_for_cpu" {
  command = plan
  variables {
    ecs_task_cpu    = 256
    ecs_task_memory = 4096
  }
  expect_failures = [var.ecs_task_memory]
}

run "reject_memory_below_cpu_minimum" {
  command = plan
  variables {
    ecs_task_cpu    = 1024
    ecs_task_memory = 1024
  }
  expect_failures = [var.ecs_task_memory]
}

run "reject_memory_off_step_for_large_cpu" {
  command = plan
  variables {
    ecs_task_cpu    = 8192
    ecs_task_memory = 17408
  }
  expect_failures = [var.ecs_task_memory]
}

run "reject_engine_version_without_minor" {
  command = plan
  variables {
    aurora_engine_version = "17"
  }
  expect_failures = [var.aurora_engine_version]
}

run "reject_instance_class_without_db_prefix" {
  command = plan
  variables {
    aurora_instance_class = "t4g.medium"
  }
  expect_failures = [var.aurora_instance_class]
}

run "reject_serverless_instance_class" {
  command = plan
  variables {
    aurora_instance_class = "db.serverless"
  }
  expect_failures = [var.aurora_instance_class]
}
