output "email_schedule_rule_arn" {
  description = "ARN of the EventBridge rule for email scheduling"
  value       = var.enable_email_notifications ? aws_cloudwatch_event_rule.email_schedule[0].arn : ""
}

output "email_schedule_rule_name" {
  description = "Name of the EventBridge rule for email scheduling"
  value       = var.enable_email_notifications ? aws_cloudwatch_event_rule.email_schedule[0].name : ""
}
