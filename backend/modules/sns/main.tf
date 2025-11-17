# EventBridge Rule for Scheduled Email Reports
# Default: Monday 9 AM UTC+8 = Monday 1 AM UTC
resource "aws_cloudwatch_event_rule" "email_schedule" {
  count = var.enable_email_notifications ? 1 : 0
  
  name                = "${var.name_prefix}-email-schedule"
  description         = "Trigger health events email summary"
  schedule_expression = var.email_schedule_expression
  
  tags = var.common_tags
}
