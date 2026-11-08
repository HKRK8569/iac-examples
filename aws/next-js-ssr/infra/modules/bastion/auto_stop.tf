data "aws_caller_identity" "auto_stop" {
  count = var.auto_stop_enabled ? 1 : 0
}

resource "aws_scheduler_schedule_group" "auto_stop" {
  count = var.auto_stop_enabled ? 1 : 0
  name  = "${var.name_prefix}-bastion-auto-stop"
  tags  = var.tags
}

resource "aws_cloudwatch_log_group" "auto_stop" {
  count             = var.auto_stop_enabled ? 1 : 0
  name              = "/aws/lambda/${var.name_prefix}-bastion-auto-stop"
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_iam_role" "auto_stop" {
  count = var.auto_stop_enabled ? 1 : 0
  name  = "${var.name_prefix}-bastion-auto-stop"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role" "auto_stop_scheduler" {
  count = var.auto_stop_enabled ? 1 : 0
  name  = "${var.name_prefix}-bastion-stop-scheduler"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "scheduler.amazonaws.com" }
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.auto_stop[0].account_id
          "aws:SourceArn"     = aws_scheduler_schedule_group.auto_stop[0].arn
        }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "auto_stop" {
  count = var.auto_stop_enabled ? 1 : 0
  role  = aws_iam_role.auto_stop[0].id
  name  = "bastion-auto-stop"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InspectInstance"
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*" # DescribeInstancesはインスタンスARNによる権限制限に非対応。
      },
      {
        Sid      = "StopOnlyBastion"
        Effect   = "Allow"
        Action   = ["ec2:StopInstances"]
        Resource = aws_instance.bastion.arn
      },
      {
        Sid      = "ManageOnlyBastionSchedules"
        Effect   = "Allow"
        Action   = ["scheduler:CreateSchedule", "scheduler:GetSchedule", "scheduler:UpdateSchedule"]
        Resource = "${replace(aws_scheduler_schedule_group.auto_stop[0].arn, ":schedule-group/", ":schedule/")}/stop-${aws_instance.bastion.id}-*"
      },
      {
        Sid      = "PassOnlySchedulerRole"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = aws_iam_role.auto_stop_scheduler[0].arn
        Condition = {
          StringEquals = { "iam:PassedToService" = "scheduler.amazonaws.com" }
        }
      },
      {
        Sid      = "WriteOwnLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.auto_stop[0].arn}:*"
      }
    ]
  })
}

locals {
  auto_stop_function_dir = abspath("${path.module}/../../../functions/bastion-auto-stop")
}

data "archive_file" "auto_stop" {
  count = var.auto_stop_enabled ? 1 : 0
  type  = "zip"
  # JavaScriptを直接ZIP化し、AWS SDKはLambdaのNode.jsランタイム同梱版を使う。
  source_dir       = "${local.auto_stop_function_dir}/src"
  output_file_mode = "0666"
  output_path      = "${path.root}/.terraform/bastion-auto-stop.zip"
}

resource "aws_lambda_function" "auto_stop" {
  count            = var.auto_stop_enabled ? 1 : 0
  function_name    = "${var.name_prefix}-bastion-auto-stop"
  role             = aws_iam_role.auto_stop[0].arn
  runtime          = "nodejs24.x"
  handler          = "index.handler"
  architectures    = ["arm64"]
  filename         = data.archive_file.auto_stop[0].output_path
  source_code_hash = data.archive_file.auto_stop[0].output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      INSTANCE_ID             = aws_instance.bastion.id
      AUTO_STOP_AFTER_MINUTES = tostring(var.auto_stop_after_minutes)
      SCHEDULE_GROUP          = aws_scheduler_schedule_group.auto_stop[0].name
      SCHEDULER_ROLE_ARN      = aws_iam_role.auto_stop_scheduler[0].arn
    }
  }

  depends_on = [aws_iam_role_policy.auto_stop]
  tags       = var.tags
}

resource "aws_iam_role_policy" "auto_stop_scheduler" {
  count = var.auto_stop_enabled ? 1 : 0
  role  = aws_iam_role.auto_stop_scheduler[0].id
  name  = "invoke-bastion-auto-stop"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = aws_lambda_function.auto_stop[0].arn
    }]
  })
}

# 起動イベントを拾い、初回作成時・イベント欠落・設定変更も定期確認で補う。
resource "aws_cloudwatch_event_rule" "auto_stop" {
  for_each = var.auto_stop_enabled ? toset(["started", "reconcile"]) : toset([])
  name     = "${var.name_prefix}-bastion-auto-stop-${each.key}"
  state    = "ENABLED"
  event_pattern = each.key == "started" ? jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance State-change Notification"]
    detail = {
      "instance-id" = [aws_instance.bastion.id]
      state         = ["running"]
    }
  }) : null
  schedule_expression = each.key == "reconcile" ? "rate(5 minutes)" : null
  tags                = var.tags
}

resource "aws_lambda_permission" "auto_stop_events" {
  for_each       = aws_cloudwatch_event_rule.auto_stop
  statement_id   = "AllowEventBridge-${each.key}"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.auto_stop[0].function_name
  principal      = "events.amazonaws.com"
  source_arn     = each.value.arn
  source_account = data.aws_caller_identity.auto_stop[0].account_id
}

resource "aws_cloudwatch_event_target" "auto_stop" {
  for_each  = aws_cloudwatch_event_rule.auto_stop
  rule      = each.value.name
  target_id = "bastion-auto-stop"
  arn       = aws_lambda_function.auto_stop[0].arn
  input     = jsonencode({ action = "reconcile" })

  retry_policy {
    maximum_event_age_in_seconds = 300
    maximum_retry_attempts       = 2
  }

  depends_on = [aws_lambda_permission.auto_stop_events, aws_iam_role_policy.auto_stop_scheduler]
}
