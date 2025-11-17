output "filters_table_name" {
  description = "Filters table name"
  value       = aws_dynamodb_table.filters.name
}

output "filters_table_arn" {
  description = "Filters table ARN"
  value       = aws_dynamodb_table.filters.arn
}

output "events_table_name" {
  description = "Events table name"
  value       = aws_dynamodb_table.events.name
}

output "events_table_arn" {
  description = "Events table ARN"
  value       = aws_dynamodb_table.events.arn
}

output "events_table_stream_arn" {
  description = "Events table DynamoDB Stream ARN"
  value       = aws_dynamodb_table.events.stream_arn
}

output "counts_table_name" {
  description = "Counts table name"
  value       = aws_dynamodb_table.counts.name
}

output "counts_table_arn" {
  description = "Counts table ARN"
  value       = aws_dynamodb_table.counts.arn
}

output "account_email_mappings_table_name" {
  description = "Account email mappings table name"
  value       = var.create_account_mappings_table ? aws_dynamodb_table.account_email_mappings[0].name : ""
}

output "account_email_mappings_table_arn" {
  description = "Account email mappings table ARN"
  value       = var.create_account_mappings_table ? aws_dynamodb_table.account_email_mappings[0].arn : ""
}

output "table_names" {
  description = "All table names"
  value = {
    filters                = aws_dynamodb_table.filters.name
    events                 = aws_dynamodb_table.events.name
    counts                 = aws_dynamodb_table.counts.name
    account_email_mappings = var.create_account_mappings_table ? aws_dynamodb_table.account_email_mappings[0].name : ""
  }
}