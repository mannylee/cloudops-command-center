output "event_processing_queue_url" {
  description = "URL of the event processing SQS queue"
  value       = aws_sqs_queue.event_processing_queue.url
}

output "event_processing_queue_arn" {
  description = "ARN of the event processing SQS queue"
  value       = aws_sqs_queue.event_processing_queue.arn
}

output "event_processing_dlq_url" {
  description = "URL of the event processing dead letter queue"
  value       = aws_sqs_queue.event_processing_dlq.url
}

output "event_processing_dlq_arn" {
  description = "ARN of the event processing dead letter queue"
  value       = aws_sqs_queue.event_processing_dlq.arn
}

output "account_email_queue_url" {
  description = "URL of the account email SQS queue"
  value       = aws_sqs_queue.account_email_queue.url
}

output "account_email_queue_arn" {
  description = "ARN of the account email SQS queue"
  value       = aws_sqs_queue.account_email_queue.arn
}

output "account_email_dlq_url" {
  description = "URL of the account email dead letter queue"
  value       = aws_sqs_queue.account_email_dlq.url
}

output "account_email_dlq_arn" {
  description = "ARN of the account email dead letter queue"
  value       = aws_sqs_queue.account_email_dlq.arn
}