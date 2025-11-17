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