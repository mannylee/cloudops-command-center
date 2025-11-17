# Data source for current account ID
data "aws_caller_identity" "current" {}

# IAM role for cross-region EventBridge forwarding
resource "aws_iam_role" "eventbridge_cross_region" {
  name = "${var.name_prefix}-eventbridge-cross-region"
  tags = var.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for cross-region EventBridge forwarding
resource "aws_iam_role_policy" "eventbridge_cross_region" {
  name = "${var.name_prefix}-eventbridge-cross-region"
  role = aws_iam_role.eventbridge_cross_region.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents"
        ]
        Resource = [
          "arn:aws:events:*:${data.aws_caller_identity.current.account_id}:event-bus/default"
        ]
      }
    ]
  })
}