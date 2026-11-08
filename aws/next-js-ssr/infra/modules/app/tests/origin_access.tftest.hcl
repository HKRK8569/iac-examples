# AWS接続・リソース作成なしで、ALBの入口がデフォルト拒否であることを検証する。
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

  mock_resource "aws_lb" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:loadbalancer/app/test/1111111111111111"
    }
  }

  mock_resource "aws_lb_listener" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:listener/app/test/1111111111111111/2222222222222222"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:targetgroup/test/3333333333333333"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/test"
    }
  }

  mock_resource "aws_ecs_cluster" {
    defaults = {
      arn = "arn:aws:ecs:ap-northeast-1:123456789012:cluster/test"
    }
  }

  mock_resource "aws_ecs_task_definition" {
    defaults = {
      arn = "arn:aws:ecs:ap-northeast-1:123456789012:task-definition/test:1"
    }
  }

  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:ap-northeast-1:123456789012:secret:test-abcdef"
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

run "deny_unverified_origin_requests" {
  command = apply

  assert {
    condition = (
      length(aws_lb_listener.http.default_action) == 1 &&
      aws_lb_listener.http.default_action[0].type == "fixed-response" &&
      aws_lb_listener.http.default_action[0].fixed_response[0].status_code == "403"
    )
    error_message = "秘密ヘッダーがない・一致しないリクエストは、デフォルトで403にする必要があります。"
  }

  assert {
    condition = (
      length(aws_lb_listener_rule.cloudfront.condition) == 1 &&
      one(aws_lb_listener_rule.cloudfront.condition).http_header[0].http_header_name == "X-Origin-Verify" &&
      one(aws_lb_listener_rule.cloudfront.condition).http_header[0].values == toset([var.origin_verify_secret]) &&
      aws_lb_listener_rule.cloudfront.listener_arn == aws_lb_listener.http.arn &&
      length(aws_lb_listener_rule.cloudfront.action) == 1 &&
      aws_lb_listener_rule.cloudfront.action[0].type == "forward" &&
      aws_lb_listener_rule.cloudfront.action[0].target_group_arn == aws_lb_target_group.this.arn
    )
    error_message = "ALBは秘密ヘッダーが一致する場合だけ、アプリのターゲットグループへ転送する必要があります。"
  }

  assert {
    condition = alltrue([
      for rule in aws_security_group.alb.ingress :
      toset(rule.prefix_list_ids) == toset([data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id]) &&
      length(coalesce(rule.cidr_blocks, [])) == 0 && length(coalesce(rule.ipv6_cidr_blocks, [])) == 0
    ]) && length(aws_security_group.alb.ingress) == 1
    error_message = "ALBの接続元は引き続きCloudFrontのマネージドプレフィックスリストに限定する必要があります。"
  }

  assert {
    condition = (
      aws_lb_target_group.this.health_check[0].path == "/api/health" &&
      aws_lb_target_group.this.health_check[0].matcher == "200"
    )
    error_message = "ALBからECSへのヘルスチェックはリスナーを通らず、従来どおり/api/healthを利用する必要があります。"
  }
}

run "reject_empty_secret" {
  command = plan
  variables {
    origin_verify_secret = ""
  }
  expect_failures = [var.origin_verify_secret]
}

run "reject_short_secret" {
  command = plan
  variables {
    origin_verify_secret = "shortSecret"
  }
  expect_failures = [var.origin_verify_secret]
}

run "reject_wildcard_secret" {
  command = plan
  variables {
    origin_verify_secret = "testOriginVerifySecret0123456789*?"
  }
  expect_failures = [var.origin_verify_secret]
}

run "reject_whitespace_in_secret" {
  command = plan
  variables {
    origin_verify_secret = "testOriginVerifySecret0123456789 abcdef"
  }
  expect_failures = [var.origin_verify_secret]
}

run "reject_oversized_secret" {
  command = plan
  variables {
    origin_verify_secret = join("", [for i in range(129) : "a"])
  }
  expect_failures = [var.origin_verify_secret]
}
