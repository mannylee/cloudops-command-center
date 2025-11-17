output "dashboard_log_group_name" {
  description = "Dashboard Lambda log group name"
  value       = aws_cloudwatch_log_group.dashboard.name
}

# output "events_log_group_name" {
#   description = "Events Lambda log group name"
#   value       = aws_cloudwatch_log_group.events.name
# }

output "filters_log_group_name" {
  description = "Filters Lambda log group name"
  value       = aws_cloudwatch_log_group.filters.name
}

# output "event_processor_log_group_name" {
#   description = "Event processor Lambda log group name"
#   value       = aws_cloudwatch_log_group.event_processor.name
# }