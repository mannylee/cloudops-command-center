# SQS Queue for event processing
resource "aws_sqs_queue" "event_processing_queue" {
  name                       = "${var.name_prefix}-event-processing-queue"
  visibility_timeout_seconds = 960  # 16 minutes (longer than Lambda timeout)
  message_retention_seconds  = 1209600  # 14 days
  
  # Enable long polling
  receive_wait_time_seconds = 20
  
  # Redrive policy for failed messages
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.event_processing_dlq.arn
    maxReceiveCount     = 3
  })

  tags = var.common_tags
}

# Dead Letter Queue for failed event processing
resource "aws_sqs_queue" "event_processing_dlq" {
  name                      = "${var.name_prefix}-event-processing-dlq"
  message_retention_seconds = 1209600  # 14 days
  
  tags = merge(var.common_tags, {
    Purpose = "Dead Letter Queue for failed event processing"
  })
}

# Dead Letter Queue for failed account email sending
resource "aws_sqs_queue" "account_email_dlq" {
  name                      = "${var.name_prefix}-account-email-dlq"
  message_retention_seconds = 1209600  # 14 days
  
  tags = merge(var.common_tags, {
    Purpose = "Dead Letter Queue for failed account email sending"
  })
}

# SQS Queue for account email processing
resource "aws_sqs_queue" "account_email_queue" {
  name                       = "${var.name_prefix}-account-email-queue"
  visibility_timeout_seconds = var.account_email_queue_visibility_timeout
  message_retention_seconds  = 345600  # 4 days
  
  # Enable long polling
  receive_wait_time_seconds = 20
  
  # Redrive policy for failed messages
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.account_email_dlq.arn
    maxReceiveCount     = 3
  })

  # Enable encryption
  sqs_managed_sse_enabled = true

  tags = var.common_tags
}

# CloudWatch Alarm for Account Email DLQ
resource "aws_cloudwatch_metric_alarm" "account_email_dlq_alarm" {
  alarm_name          = "${var.name_prefix}-account-email-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Alert when messages appear in account email DLQ"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.account_email_dlq.name
  }

  tags = var.common_tags
}