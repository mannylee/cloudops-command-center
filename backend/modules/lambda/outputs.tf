output "dashboard_function_arn" {
  description = "Dashboard Lambda function ARN"
  value       = aws_lambda_function.dashboard.arn
}

output "events_function_arn" {
  description = "Events Lambda function ARN"
  value       = aws_lambda_function.events.arn
}

output "filters_function_arn" {
  description = "Filters Lambda function ARN"
  value       = aws_lambda_function.filters.arn
}

output "event_processor_function_arn" {
  description = "Event processor Lambda function ARN"
  value       = aws_lambda_function.event_processor.arn
}

output "dashboard_function_name" {
  description = "Dashboard Lambda function name"
  value       = aws_lambda_function.dashboard.function_name
}

output "events_function_name" {
  description = "Events Lambda function name"
  value       = aws_lambda_function.events.function_name
}

output "filters_function_name" {
  description = "Filters Lambda function name"
  value       = aws_lambda_function.filters.function_name
}

output "event_processor_function_name" {
  description = "Event processor Lambda function name"
  value       = aws_lambda_function.event_processor.function_name
}

output "function_names" {
  description = "All Lambda function names"
  value = {
    dashboard       = aws_lambda_function.dashboard.function_name
    events          = aws_lambda_function.events.function_name
    filters         = aws_lambda_function.filters.function_name
    event_processor = aws_lambda_function.event_processor.function_name
  }
}

output "email_processor_function_arn" {
  description = "Email processor Lambda function ARN"
  value       = var.enable_email_notifications ? aws_lambda_function.email_processor[0].arn : ""
}

output "email_processor_function_name" {
  description = "Email processor Lambda function name"
  value       = var.enable_email_notifications ? aws_lambda_function.email_processor[0].function_name : ""
}

output "account_email_sender_function_arn" {
  description = "Account email sender Lambda function ARN"
  value       = var.enable_email_notifications ? aws_lambda_function.account_email_sender[0].arn : ""
}

output "account_email_sender_function_name" {
  description = "Account email sender Lambda function name"
  value       = var.enable_email_notifications ? aws_lambda_function.account_email_sender[0].function_name : ""
}