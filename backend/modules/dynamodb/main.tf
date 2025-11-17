# DynamoDB table for filters
resource "aws_dynamodb_table" "filters" {
  name           = "${var.name_prefix}-filters"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "filterId"

  attribute {
    name = "filterId"
    type = "S"
  }

  tags = merge(var.common_tags, {
    Name        = "${var.name_prefix}-filters"
    Environment = var.environment
  })
}

# DynamoDB table for PHD events
resource "aws_dynamodb_table" "events" {
  name           = "${var.name_prefix}-events"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "eventArn"
  range_key      = "accountId"

  attribute {
    name = "eventArn"
    type = "S"
  }

  attribute {
    name = "accountId"
    type = "S"
  }

  attribute {
    name = "eventTypeCategory"
    type = "S"
  }

  attribute {
    name = "lastUpdateTime"
    type = "S"
  }

  # GSI for efficient querying by category and time
  global_secondary_index {
    name            = "CategoryTimeIndex"
    hash_key        = "eventTypeCategory"
    range_key       = "lastUpdateTime"
    projection_type = "ALL"
  }

  # Enable TTL for automatic deletion of old events (6 months retention)
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  # Enable DynamoDB Streams to capture TTL deletions for count updates
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  tags = merge(var.common_tags, {
    Name        = "${var.name_prefix}-events"
    Environment = var.environment
  })
}

# DynamoDB table for count tracking
resource "aws_dynamodb_table" "counts" {
  name           = "${var.name_prefix}-counts"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "accountId"
  # Removed range_key to simplify the table structure for live counts

  attribute {
    name = "accountId"
    type = "S"
  }

  tags = merge(var.common_tags, {
    Name        = "${var.name_prefix}-counts"
    Environment = var.environment
  })
}

# DynamoDB table for account email mappings
resource "aws_dynamodb_table" "account_email_mappings" {
  count          = var.create_account_mappings_table ? 1 : 0
  name           = "${var.name_prefix}-account-email-mappings"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "accountId"

  attribute {
    name = "accountId"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(var.common_tags, {
    Name        = "${var.name_prefix}-account-email-mappings"
    Environment = var.environment
  })
}