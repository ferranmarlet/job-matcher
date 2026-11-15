# ──────────────────────────────────────────
# Shared infrastructure from the jobscan API stack
# ──────────────────────────────────────────
# Apply the API stack (../../jobscan/terraform) first.
data "terraform_remote_state" "api" {
  backend = "local"

  config = {
    path = var.api_state_path
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_ecs_cluster" "main" {
  cluster_name = data.terraform_remote_state.api.outputs.ecs_cluster_name
}

# The public subnet: it has an Internet Gateway route, so a task with a public IP
# reaches S3, Bedrock, ECR and CloudWatch without a NAT gateway.
data "aws_subnet" "public" {
  vpc_id = data.terraform_remote_state.api.outputs.vpc_id

  filter {
    name   = "tag:Name"
    values = ["${var.api_project_name}-public-a"]
  }
}

data "aws_db_instance" "main" {
  db_instance_identifier = "${var.api_project_name}-${var.environment}"
}

locals {
  name       = "${var.project_name}-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # jobscan-app-sg: the only group the RDS security group accepts on 5432.
  # Its egress is open, which the task needs for S3, Bedrock, ECR and logs.
  task_security_group_ids = [data.terraform_remote_state.api.outputs.app_security_group_id]
}

# ──────────────────────────────────────────
# Image registry
# ──────────────────────────────────────────
resource "aws_ecr_repository" "app" {
  name                 = local.name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Keeps storage costs down by expiring old images
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the 5 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

# ──────────────────────────────────────────
# Logs
# ──────────────────────────────────────────
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name}"
  retention_in_days = var.log_retention_days
}

# ──────────────────────────────────────────
# IAM: task execution role (used by ECS to start the task)
# ──────────────────────────────────────────
resource "aws_iam_role" "task_execution" {
  name        = "${local.name}-task-execution"
  description = "Lets ECS pull the job-matcher image and write its logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ──────────────────────────────────────────
# IAM: task role (used by the job's code)
# ──────────────────────────────────────────
resource "aws_iam_role" "task" {
  name        = "${local.name}-task"
  description = "Role assumed by the job-matcher task: read the input file, connect to RDS, call Claude"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy" "task" {
  name = "job-matcher"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadInputFile"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "arn:${local.partition}:s3:::${var.input_bucket_name}/${var.input_key_prefix}*"
      },
      {
        # Lets the job find the newest file under the prefix
        Sid      = "ListInputFiles"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:${local.partition}:s3:::${var.input_bucket_name}"
        Condition = {
          StringLike = { "s3:prefix" = ["${var.input_key_prefix}*"] }
        }
      },
      {
        Sid      = "ConnectToDatabase"
        Effect   = "Allow"
        Action   = "rds-db:connect"
        Resource = "arn:${local.partition}:rds-db:${var.aws_region}:${local.account_id}:dbuser:${data.aws_db_instance.main.resource_id}/${var.db_app_username}"
      },
      {
        # Claude in Amazon Bedrock (bedrock-mantle endpoint), limited to one model
        Sid      = "InvokeClaude"
        Effect   = "Allow"
        Action   = "bedrock-mantle:CreateInference"
        Resource = "arn:${local.partition}:bedrock-mantle:${var.aws_region}:${local.account_id}:project/*"
        Condition = {
          StringEquals = { "bedrock-mantle:Model" = var.bedrock_model_id }
        }
      },
    ]
  })
}

# ──────────────────────────────────────────
# Task definition
# ──────────────────────────────────────────
resource "aws_ecs_task_definition" "app" {
  family                   = local.name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  container_definitions = jsonencode([{
    name      = var.project_name
    image     = "${aws_ecr_repository.app.repository_url}:${var.container_image_tag}"
    essential = true

    environment = [
      { name = "NODE_ENV", value = "production" },
      { name = "AWS_REGION", value = var.aws_region },
      { name = "DB_HOST", value = data.aws_db_instance.main.address },
      { name = "DB_PORT", value = tostring(data.aws_db_instance.main.port) },
      { name = "DB_NAME", value = data.aws_db_instance.main.db_name },
      { name = "DB_USER", value = var.db_app_username },
      { name = "INPUT_BUCKET", value = var.input_bucket_name },
      { name = "INPUT_KEY_PREFIX", value = var.input_key_prefix },
      { name = "CLAUDE_MODEL", value = var.bedrock_model_id },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

# ──────────────────────────────────────────
# IAM: role that starts the task, shared by the schedule and the manual-run rule
# ──────────────────────────────────────────
resource "aws_iam_role" "run_task" {
  name        = "${local.name}-run-task"
  description = "Lets EventBridge Scheduler and EventBridge rules start the job-matcher task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = ["scheduler.amazonaws.com", "events.amazonaws.com"] }
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy" "run_task" {
  name = "run-job-matcher-task"
  role = aws_iam_role.run_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecs:RunTask"
        Resource = "${aws_ecs_task_definition.app.arn_without_revision}:*"
        Condition = {
          ArnEquals = { "ecs:cluster" = data.aws_ecs_cluster.main.arn }
        }
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = [aws_iam_role.task_execution.arn, aws_iam_role.task.arn]
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      },
    ]
  })
}

# ──────────────────────────────────────────
# Trigger 1: schedule (EventBridge Scheduler → ecs:RunTask)
# ──────────────────────────────────────────
resource "aws_scheduler_schedule" "run" {
  name                         = local.name
  description                  = "Runs the job-matcher task"
  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = var.schedule_timezone
  state                        = var.schedule_enabled ? "ENABLED" : "DISABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = data.aws_ecs_cluster.main.arn
    role_arn = aws_iam_role.run_task.arn

    ecs_parameters {
      # Without a revision, each run uses the latest ACTIVE revision
      task_definition_arn = aws_ecs_task_definition.app.arn_without_revision
      launch_type         = "FARGATE"
      platform_version    = "LATEST"
      task_count          = 1

      network_configuration {
        subnets          = [data.aws_subnet.public.id]
        security_groups  = local.task_security_group_ids
        assign_public_ip = true
      }
    }

    # Retries only failures to start the task, not a task that exits with an error
    retry_policy {
      maximum_retry_attempts       = 2
      maximum_event_age_in_seconds = 3600
    }
  }
}

# ──────────────────────────────────────────
# Trigger 2: manual run (an event on the default bus → ecs:RunTask)
# ──────────────────────────────────────────
# Start a run with: aws events put-events (see the put_event_command output).
resource "aws_cloudwatch_event_rule" "manual_run" {
  name        = "${local.name}-manual-run"
  description = "Starts the job-matcher task when a run is requested by event"

  event_pattern = jsonencode({
    source      = [var.manual_event_source]
    detail-type = [var.manual_event_detail_type]
  })
}

resource "aws_cloudwatch_event_target" "manual_run" {
  rule     = aws_cloudwatch_event_rule.manual_run.name
  arn      = data.aws_ecs_cluster.main.arn
  role_arn = aws_iam_role.run_task.arn

  ecs_target {
    # Without a revision, each run uses the latest ACTIVE revision
    task_definition_arn = aws_ecs_task_definition.app.arn_without_revision
    launch_type         = "FARGATE"
    platform_version    = "LATEST"
    task_count          = 1

    network_configuration {
      subnets          = [data.aws_subnet.public.id]
      security_groups  = local.task_security_group_ids
      assign_public_ip = true
    }
  }

  # Retries only failures to start the task, not a task that exits with an error
  retry_policy {
    maximum_retry_attempts       = 2
    maximum_event_age_in_seconds = 3600
  }
}

# ──────────────────────────────────────────
# Alerts: a run that fails to start or exits non-zero
# ──────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  count = var.alert_email == null ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_event_rule" "task_failed" {
  name        = "${local.name}-task-failed"
  description = "A job-matcher task failed to start or exited with a non-zero code"

  event_pattern = jsonencode({
    source      = ["aws.ecs"]
    detail-type = ["ECS Task State Change"]
    detail = {
      clusterArn = [data.aws_ecs_cluster.main.arn]
      group      = ["family:${aws_ecs_task_definition.app.family}"]
      lastStatus = ["STOPPED"]
      "$or" = [
        { containers = { exitCode = [{ "anything-but" = 0 }] } },
        { stopCode = ["TaskFailedToStart"] },
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "task_failed" {
  rule = aws_cloudwatch_event_rule.task_failed.name
  arn  = aws_sns_topic.alerts.arn

  input_transformer {
    input_paths = {
      task     = "$.detail.taskArn"
      reason   = "$.detail.stoppedReason"
      exitCode = "$.detail.containers[0].exitCode"
    }
    input_template = "\"job-matcher task <task> failed: <reason> (exit code <exitCode>). Logs: ${aws_cloudwatch_log_group.app.name}\""
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sns:Publish"
      Principal = { Service = "events.amazonaws.com" }
      Resource  = aws_sns_topic.alerts.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.task_failed.arn }
      }
    }]
  })
}
