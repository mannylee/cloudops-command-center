terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Data source for current region
data "aws_region" "current" {}

# Local to determine if this is the deployment region
locals {
  is_deployment_region = var.current_region == var.deployment_region
}

# EventBridge rule for AWS Health events
resource "aws_cloudwatch_event_rule" "health_events" {
  name        = "${var.name_prefix}-health-events"
  tags        = var.common_tags
  description = "Capture AWS Health events"

  event_pattern = jsonencode({
    source = ["aws.health"]
    detail-type = [
      "AWS Health Event",
      "AWS Health Abuse Event"
    ]
  })
}

# EventBridge target for SQS Queue (only in deployment region)
resource "aws_cloudwatch_event_target" "sqs_target" {
  count     = local.is_deployment_region ? 1 : 0
  rule      = aws_cloudwatch_event_rule.health_events.name
  target_id = "HealthEventSQSProcessor"
  arn       = var.sqs_queue_arn

  # Ensure this target is destroyed before the rule
  lifecycle {
    create_before_destroy = false
  }
}

# EventBridge target for forwarding to deployment region (only in non-deployment regions)
resource "aws_cloudwatch_event_target" "eventbridge_target" {
  count     = !local.is_deployment_region ? 1 : 0
  rule      = aws_cloudwatch_event_rule.health_events.name
  target_id = "ForwardToDeploymentRegion"
  arn       = "arn:aws:events:${var.deployment_region}:${var.account_id}:event-bus/default"

  role_arn = var.eventbridge_role_arn

  # Ensure this target is destroyed before the rule
  lifecycle {
    create_before_destroy = false
  }
}

# EventBridge Scheduled Rule for Event Sync (only in deployment region)
# Periodically syncs event status changes from AWS Health API
resource "aws_cloudwatch_event_rule" "event_sync_schedule" {
  count = local.is_deployment_region ? 1 : 0

  name                = "${var.name_prefix}-sync-sched"
  description         = "Trigger event processor to sync status changes from AWS Health API"
  schedule_expression = var.event_sync_schedule_expression

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-sync-sched"
  })
}

# EventBridge Target for Event Sync (only in deployment region)
resource "aws_cloudwatch_event_target" "event_sync_target" {
  count = local.is_deployment_region ? 1 : 0

  rule      = aws_cloudwatch_event_rule.event_sync_schedule[0].name
  target_id = "EventProcessorSync"
  arn       = var.event_processor_function_arn

  input = jsonencode({
    mode          = "scheduled_sync"
    lookback_days = var.event_sync_lookback_days
  })
}

# Lambda Permission for EventBridge Sync (only in deployment region)
resource "aws_lambda_permission" "allow_eventbridge_sync" {
  count = local.is_deployment_region ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridgeSync"
  action        = "lambda:InvokeFunction"
  function_name = var.event_processor_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.event_sync_schedule[0].arn
}