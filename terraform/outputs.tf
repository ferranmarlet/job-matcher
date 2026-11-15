output "ecr_repository_url" {
  description = "ECR repository to push the job-matcher image to"
  value       = aws_ecr_repository.app.repository_url
}

output "task_definition_family" {
  description = "Task definition family; runs use its latest ACTIVE revision"
  value       = aws_ecs_task_definition.app.family
}

output "log_group_name" {
  description = "CloudWatch log group of the task"
  value       = aws_cloudwatch_log_group.app.name
}

output "alerts_topic_arn" {
  description = "SNS topic notified when a run fails"
  value       = aws_sns_topic.alerts.arn
}

output "put_event_command" {
  description = "Starts one run by sending the manual-run event to EventBridge"
  value = join(" ", [
    "aws events put-events",
    "--region ${var.aws_region}",
    "--entries '${jsonencode([{ Source = var.manual_event_source, DetailType = var.manual_event_detail_type, Detail = "{}" }])}'",
  ])
}

output "run_task_command" {
  description = "Starts one run directly through ECS, bypassing EventBridge"
  value = join(" ", [
    "aws ecs run-task",
    "--region ${var.aws_region}",
    "--cluster ${data.aws_ecs_cluster.main.cluster_name}",
    "--task-definition ${aws_ecs_task_definition.app.family}",
    "--launch-type FARGATE",
    "--network-configuration 'awsvpcConfiguration={subnets=[${data.aws_subnet.public.id}],securityGroups=[${join(",", local.task_security_group_ids)}],assignPublicIp=ENABLED}'",
  ])
}
