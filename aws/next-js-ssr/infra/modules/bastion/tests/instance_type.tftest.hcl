# planのみ・AWSプロバイダーはモック。実リソースの作成や削除は行わない。
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
}

variables {
  name_prefix = "next-js-ssr-test"
  vpc_id      = "vpc-0123456789abcdef0"
  subnet_id   = "subnet-0123456789abcdef0"
}

run "default_is_t4g_nano" {
  command = plan
  assert {
    condition     = aws_instance.bastion.instance_type == "t4g.nano"
    error_message = "踏み台の既定値は変数化前と同じt4g.nanoである必要があります。"
  }
}

run "accept_other_graviton_types" {
  command = plan
  variables {
    instance_type = "m7g.medium"
  }
  assert {
    condition     = aws_instance.bastion.instance_type == "m7g.medium"
    error_message = "指定したGraviton系のインスタンスタイプが反映される必要があります。"
  }
}

run "reject_x86_instance_type" {
  command = plan
  variables {
    instance_type = "t3.micro"
  }
  expect_failures = [var.instance_type]
}

run "reject_malformed_instance_type" {
  command = plan
  variables {
    instance_type = "t4g"
  }
  expect_failures = [var.instance_type]
}
