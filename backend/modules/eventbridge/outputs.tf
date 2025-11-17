output "rule_name" {
  description = "EventBridge rule name"
  value       = aws_cloudwatch_event_rule.health_events.name
}

output "rule_arn" {
  description = "EventBridge rule ARN"
  value       = aws_cloudwatch_event_rule.health_events.arn
}