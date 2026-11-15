variable "aws_region" {
  description = "AWS region to deploy into, which must match the API stack's region"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Project name, used for naming and tagging resources"
  type        = string
  default     = "job-matcher"
}

variable "environment" {
  description = "Environment name, which must match the API stack's environment"
  type        = string
  default     = "dev"
}

# ──────────────────────────────────────────
# Shared infrastructure (jobscan API stack)
# ──────────────────────────────────────────
variable "api_project_name" {
  description = "Project name of the jobscan API stack, used to find its subnet and RDS instance"
  type        = string
  default     = "jobscan"
}

variable "api_state_path" {
  description = "Path to the jobscan API stack's Terraform state file"
  type        = string
  default     = "../../jobscan/terraform/terraform.tfstate"
}

# ──────────────────────────────────────────
# Database
# ──────────────────────────────────────────
variable "db_app_username" {
  description = "PostgreSQL user the job authenticates as with an IAM token (must be granted rds_iam)"
  type        = string
  default     = "job_matcher"
}

# ──────────────────────────────────────────
# Input file
# ──────────────────────────────────────────
variable "input_bucket_name" {
  description = "Name of the existing S3 bucket the job downloads its input file from"
  type        = string
}

variable "input_key_prefix" {
  description = "Key prefix the job may read under (e.g. \"exports/\"). Empty allows the whole bucket."
  type        = string
  default     = ""
}

# ──────────────────────────────────────────
# AI model (Claude in Amazon Bedrock)
# ──────────────────────────────────────────
variable "bedrock_model_id" {
  description = "Claude model the job calls on the bedrock-mantle endpoint"
  type        = string
  default     = "anthropic.claude-haiku-5-5"
}

# ──────────────────────────────────────────
# Task
# ──────────────────────────────────────────
variable "container_image_tag" {
  description = "Tag of the image in the ECR repository to run"
  type        = string
  default     = "latest"
}

variable "task_cpu" {
  description = "Fargate task CPU units (1024 = 1 vCPU)"
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "Fargate task memory in MiB; must be a valid combination with task_cpu"
  type        = number
  default     = 1024
}

variable "cpu_architecture" {
  description = "CPU architecture of the image: X86_64, or ARM64 for an image built for arm64 (about 20% cheaper)"
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "Must be X86_64 or ARM64."
  }
}

variable "log_retention_days" {
  description = "Days to keep the task's CloudWatch logs"
  type        = number
  default     = 7
}

# ──────────────────────────────────────────
# Schedule
# ──────────────────────────────────────────
variable "schedule_expression" {
  description = "When the job runs: an EventBridge Scheduler cron(...) or rate(...) expression"
  type        = string
  default     = "cron(0 11 ? * MON *)"
}

variable "schedule_timezone" {
  description = "Time zone the schedule expression is evaluated in"
  type        = string
  default     = "Europe/Madrid"
}

variable "schedule_enabled" {
  description = "Whether the schedule fires. Set false to only run the job by hand."
  type        = bool
  default     = true
}

# ──────────────────────────────────────────
# Manual run (event on the default EventBridge bus)
# ──────────────────────────────────────────
variable "manual_event_source" {
  description = "Source of the event that starts a run by hand (must not start with \"aws.\")"
  type        = string
  default     = "job-matcher"
}

variable "manual_event_detail_type" {
  description = "Detail type of the event that starts a run by hand"
  type        = string
  default     = "Run requested"
}

# ──────────────────────────────────────────
# Alerts
# ──────────────────────────────────────────
variable "alert_email" {
  description = "Email notified when a run fails. Null creates the topic without a subscription."
  type        = string
  default     = null
}
