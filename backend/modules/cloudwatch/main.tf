# CloudWatch Log Groups for Lambda Functions
resource "aws_cloudwatch_log_group" "dashboard" {
  name              = "/aws/lambda/${var.dashboard_function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-dashboard-logs"
  })
}

resource "aws_cloudwatch_log_group" "events" {
  name              = "/aws/lambda/${var.events_function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-events-logs"
  })
}

resource "aws_cloudwatch_log_group" "filters" {
  name              = "/aws/lambda/${var.filters_function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-filters-logs"
  })
}

resource "aws_cloudwatch_log_group" "event_processor" {
  name              = "/aws/lambda/${var.event_processor_function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-event-processor-logs"
  })
}

# EventBridge Scheduled Rule for Event Sync
# Periodically syncs event status changes from AWS Health API
resource "aws_cloudwatch_event_rule" "event_sync_schedule" {
  name                = "${var.name_prefix}-event-sync-schedule"
  description         = "Trigger event processor to sync status changes from AWS Health API"
  schedule_expression = var.event_sync_schedule_expression

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-event-sync-schedule"
  })
}

# EventBridge Target for Event Sync
resource "aws_cloudwatch_event_target" "event_sync_target" {
  rule      = aws_cloudwatch_event_rule.event_sync_schedule.name
  target_id = "EventProcessorSync"
  arn       = var.event_processor_function_arn

  input = jsonencode({
    mode          = "scheduled_sync"
    lookback_days = var.event_sync_lookback_days
  })
}

# Lambda Permission for EventBridge Sync
resource "aws_lambda_permission" "allow_eventbridge_sync" {
  statement_id  = "AllowExecutionFromEventBridgeSync"
  action        = "lambda:InvokeFunction"
  function_name = var.event_processor_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.event_sync_schedule.arn
}
