mock_provider "aws" {
  mock_data "aws_ami" {
    defaults = { id = "ami-0123456789abcdef0" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_instance" {
    defaults = {
      id  = "i-0123456789abcdef0"
      arn = "arn:aws:ec2:ap-northeast-1:123456789012:instance/i-0123456789abcdef0"
    }
  }
  mock_resource "aws_scheduler_schedule_group" {
    defaults = { arn = "arn:aws:scheduler:ap-northeast-1:123456789012:schedule-group/next-js-ssr-test-bastion-auto-stop" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/test" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:ap-northeast-1:123456789012:function:auto-stop" }
  }
  mock_resource "aws_cloudwatch_event_rule" {
    defaults = { arn = "arn:aws:events:ap-northeast-1:123456789012:rule/bastion-auto-stop" }
  }
}

variables {
  name_prefix = "next-js-ssr-test"
  vpc_id      = "vpc-0123456789abcdef0"
  subnet_id   = "subnet-0123456789abcdef0"
}

run "disabled_by_default" {
  command = plan
  assert {
    condition = (
      length(aws_lambda_function.auto_stop) == 0 &&
      length(aws_cloudwatch_event_rule.auto_stop) == 0 &&
      length(aws_cloudwatch_event_target.auto_stop) == 0 &&
      length(aws_lambda_permission.auto_stop_events) == 0 &&
      length(aws_scheduler_schedule_group.auto_stop) == 0 &&
      length(aws_iam_role.auto_stop) == 0 && length(aws_iam_role.auto_stop_scheduler) == 0 &&
      length(aws_iam_role_policy.auto_stop) == 0 && length(aws_iam_role_policy.auto_stop_scheduler) == 0 &&
      length(aws_cloudwatch_log_group.auto_stop) == 0 && length(data.archive_file.auto_stop) == 0
    )
    error_message = "無効時は自動停止用リソースとZIPを作成してはいけません。"
  }
}

run "enabled_limits_permissions_and_detects_every_start" {
  command = apply
  variables {
    auto_stop_enabled = true
  }
  assert {
    condition = (
      aws_lambda_function.auto_stop[0].environment[0].variables["INSTANCE_ID"] == aws_instance.bastion.id &&
      aws_lambda_function.auto_stop[0].environment[0].variables["AUTO_STOP_AFTER_MINUTES"] == "60" &&
      aws_lambda_function.auto_stop[0].runtime == "nodejs24.x" &&
      aws_lambda_function.auto_stop[0].handler == "index.handler" &&
      aws_lambda_function.auto_stop[0].reserved_concurrent_executions == 1 &&
      aws_cloudwatch_log_group.auto_stop[0].retention_in_days == 7
    )
    error_message = "Lambdaは対象の踏み台と既定60分を使い、予約の同時更新を抑制し、ログを管理する必要があります。"
  }
  assert {
    condition = (
      jsondecode(aws_cloudwatch_event_rule.auto_stop["started"].event_pattern).detail["instance-id"] == [aws_instance.bastion.id] &&
      jsondecode(aws_cloudwatch_event_rule.auto_stop["started"].event_pattern).detail.state == ["running"] &&
      aws_cloudwatch_event_rule.auto_stop["reconcile"].schedule_expression == "rate(5 minutes)" &&
      length(aws_cloudwatch_event_target.auto_stop) == 2 &&
      alltrue([for target in aws_cloudwatch_event_target.auto_stop :
        target.arn == aws_lambda_function.auto_stop[0].arn && jsondecode(target.input).action == "reconcile"
      ])
    )
    error_message = "対象インスタンスの起動を検知し、初回作成・イベント欠落を5分ごとの確認で補う必要があります。"
  }
  assert {
    condition = length([
      for statement in jsondecode(aws_iam_role_policy.auto_stop[0].policy).Statement :
      statement if statement.Sid == "StopOnlyBastion"
      ]) == 1 && alltrue([
      for statement in jsondecode(aws_iam_role_policy.auto_stop[0].policy).Statement :
      statement.Sid == "StopOnlyBastion" ? (
        statement.Action == ["ec2:StopInstances"] && statement.Resource == aws_instance.bastion.arn
        ) : statement.Sid == "ManageOnlyBastionSchedules" ? (
        statement.Resource == "arn:aws:scheduler:ap-northeast-1:123456789012:schedule/next-js-ssr-test-bastion-auto-stop/stop-${aws_instance.bastion.id}-*"
        ) : statement.Sid == "PassOnlySchedulerRole" ? (
        statement.Resource == aws_iam_role.auto_stop_scheduler[0].arn &&
        statement.Condition.StringEquals["iam:PassedToService"] == "scheduler.amazonaws.com"
      ) : true
    ])
    error_message = "停止権限・予約管理権限・PassRoleは、この踏み台と専用ロールに限定する必要があります。"
  }
  assert {
    condition = (
      jsondecode(aws_iam_role.auto_stop_scheduler[0].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceArn"] == aws_scheduler_schedule_group.auto_stop[0].arn &&
      jsondecode(aws_iam_role.auto_stop_scheduler[0].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012" &&
      jsondecode(aws_iam_role_policy.auto_stop_scheduler[0].policy).Statement[0].Resource == aws_lambda_function.auto_stop[0].arn &&
      alltrue([for permission in aws_lambda_permission.auto_stop_events :
        permission.principal == "events.amazonaws.com" && permission.source_account == "123456789012"
      ])
    )
    error_message = "Schedulerの信頼先は自分のアカウント・専用グループ、呼び出し先は専用Lambdaに限定する必要があります。"
  }
}

run "custom_duration" {
  command = plan
  variables {
    auto_stop_enabled       = true
    auto_stop_after_minutes = 15
  }
  assert {
    condition     = aws_lambda_function.auto_stop[0].environment[0].variables["AUTO_STOP_AFTER_MINUTES"] == "15"
    error_message = "環境から指定した停止までの分数をLambdaへ渡す必要があります。"
  }
}

run "reject_zero_minutes" {
  command = plan
  variables { auto_stop_after_minutes = 0 }
  expect_failures = [var.auto_stop_after_minutes]
}

run "reject_negative_minutes" {
  command = plan
  variables { auto_stop_after_minutes = -1 }
  expect_failures = [var.auto_stop_after_minutes]
}

run "reject_fractional_minutes" {
  command = plan
  variables { auto_stop_after_minutes = 1.5 }
  expect_failures = [var.auto_stop_after_minutes]
}

run "reject_excessive_minutes" {
  command = plan
  variables { auto_stop_after_minutes = 1441 }
  expect_failures = [var.auto_stop_after_minutes]
}

run "accept_minimum_duration" {
  command = plan
  variables { auto_stop_after_minutes = 1 }
}

run "accept_maximum_duration" {
  command = plan
  variables { auto_stop_after_minutes = 1440 }
}
