resource "aws_security_group" "app" {
  name   = "${var.name_prefix}-app-sg"
  vpc_id = var.vpc_id

  ingress {
    # ALBからのコンテナのポートを許可
    description     = "Allow container port from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    # アウトバウンドを全て許可する
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-app-sg"
  })
}

resource "aws_ecs_task_definition" "this" {
  family                   = "${var.name_prefix}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  cpu    = 256
  memory = 512

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  # アプリ自身がAWS APIを呼ぶ用（S3の署名付きURL発行など）
  task_role_arn = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = var.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "NODE_ENV", value = "production" },
        { name = "PORT", value = tostring(var.container_port) }
      ]

      # Secrets ManagerからDB接続情報を注入する（起動時に実行ロールで取得される）
      secrets = [
        { name = "DB_NAME", valueFrom = "${aws_secretsmanager_secret.database.arn}:db_name::" },
        { name = "DB_USERNAME", valueFrom = "${aws_secretsmanager_secret.database.arn}:username::" },
        { name = "DB_PASSWORD", valueFrom = "${aws_secretsmanager_secret.database.arn}:password::" },
        { name = "DB_WRITER_ENDPOINT", valueFrom = "${aws_secretsmanager_secret.database.arn}:writer_endpoint::" },
        { name = "DB_READER_ENDPOINT", valueFrom = "${aws_secretsmanager_secret.database.arn}:reader_endpoint::" },
        { name = "DB_PORT", valueFrom = "${aws_secretsmanager_secret.database.arn}:port::" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-task"
  })
}

resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-ecs-cluster"
}


resource "aws_ecs_service" "this" {
  name            = "${var.name_prefix}-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  # 冗長化ONなら各AZに一つ、OFFなら1つ
  desired_count = var.multi_az ? 2 : 1

  launch_type = "FARGATE"

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.http]
}


resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.name_prefix}"
  retention_in_days = 7
}
