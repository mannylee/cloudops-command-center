output "dashboard_role_arn" {
  description = "Dashboard Lambda role ARN"
  value       = aws_iam_role.dashboard_role.arn
}

output "events_role_arn" {
  description = "Events Lambda role ARN"
  value       = aws_iam_role.events_role.arn
}

output "filters_role_arn" {
  description = "Filters Lambda role ARN"
  value       = aws_iam_role.filters_role.arn
}

output "event_processor_role_arn" {
  description = "Event Processor Lambda role ARN"
  value       = aws_iam_role.event_processor_role.arn
}

output "eventbridge_cross_region_role_arn" {
  description = "ARN of the EventBridge cross-region role"
  value       = aws_iam_role.eventbridge_cross_region.arn
}

# EventBridge permission outputs removed - permissions now managed in main.tf

output "email_processor_role_arn" {
  description = "Email Processor Lambda role ARN"
  value       = var.enable_email_notifications ? aws_iam_role.email_processor_role[0].arn : ""
}

output "account_email_sender_role_arn" {
  description = "Account Email Sender Lambda role ARN"
  value       = var.enable_email_notifications ? aws_iam_role.account_email_sender_role[0].arn : ""
}