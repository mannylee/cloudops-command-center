output "rule_name" {
  description = "EventBridge rule name for health events"
  value       = aws_cloudwatch_event_rule.health_events.name
}

output "rule_arn" {
  description = "EventBridge rule ARN for health events"
  value       = aws_cloudwatch_event_rule.health_events.arn
}

output "event_sync_schedule_rule_arn" {
  description = "ARN of the EventBridge rule for event sync scheduling (only in deployment region)"
  value       = length(aws_cloudwatch_event_rule.event_sync_schedule) > 0 ? aws_cloudwatch_event_rule.event_sync_schedule[0].arn : null
}

output "event_sync_schedule_rule_name" {
  description = "Name of the EventBridge rule for event sync scheduling (only in deployment region)"
  value       = length(aws_cloudwatch_event_rule.event_sync_schedule) > 0 ? aws_cloudwatch_event_rule.event_sync_schedule[0].name : null
}