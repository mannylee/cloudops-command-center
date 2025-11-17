# Dashboard Lambda role
resource "aws_iam_role" "dashboard_role" {
  name = "${var.name_prefix}-dashboard-role"
  tags = var.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "dashboard_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.dashboard_role.name
}

resource "aws_iam_role_policy" "dashboard_dynamodb" {
  name = "${var.name_prefix}-dashboard-dynamodb"
  role = aws_iam_role.dashboard_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:BatchGetItem"
        ]
        Resource = [var.counts_table_arn, var.filters_table_arn]
      }
    ]
  })
}

# Events Lambda role
resource "aws_iam_role" "events_role" {
  name = "${var.name_prefix}-events-role"
  tags = var.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "events_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.events_role.name
}

resource "aws_iam_role_policy" "events_health" {
  name = "${var.name_prefix}-events-health"
  role = aws_iam_role.events_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "health:DescribeEvents",
          "health:DescribeEventDetails",
          "health:DescribeAffectedEntities",
          "health:DescribeEventAggregates",
          "organizations:ListAccounts",
          "organizations:DescribeOrganization"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "events_dynamodb" {
  name = "${var.name_prefix}-events-dynamodb"
  role = aws_iam_role.events_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Resource = [
          var.events_table_arn,
          "${var.events_table_arn}/index/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "events_lambda_invoke" {
  name = "${var.name_prefix}-events-lambda-invoke"
  role = aws_iam_role.events_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "arn:aws:lambda:*:*:function:${var.name_prefix}-filters-api"
      }
    ]
  })
}

# Filters Lambda role
resource "aws_iam_role" "filters_role" {
  name = "${var.name_prefix}-filters-role"
  tags = var.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "filters_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.filters_role.name
}

resource "aws_iam_role_policy" "filters_dynamodb" {
  name = "${var.name_prefix}-filters-dynamodb"
  role = aws_iam_role.filters_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:BatchGetItem"
        ]
        Resource = [var.filters_table_arn]
      }
    ]
  })
}

# Event Processor Lambda role
resource "aws_iam_role" "event_processor_role" {
  name = "${var.name_prefix}-event-processor-role"
  tags = var.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "event_processor_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.event_processor_role.name
}

resource "aws_iam_role_policy" "event_processor_dynamodb" {
  name = "${var.name_prefix}-event-processor-dynamodb"
  role = aws_iam_role.event_processor_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Resource = [
          var.events_table_arn,
          var.counts_table_arn,
          "${var.events_table_arn}/index/*",
          "${var.events_table_arn}/stream/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeStream",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:ListStreams"
        ]
        Resource = [
          "${var.events_table_arn}/stream/*"
        ]
      }
    ]
  })
}

locals {
  # Determine region prefix based on deployment region
  region_prefix = var.deployment_region == "ap-southeast-1" ? "apac" : "us"
  
  # Define Bedrock model ARNs based on region
  bedrock_foundation_models = [
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-20250514-v1:0",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-3-7-sonnet-20250219-v1:0"
  ]
  
  bedrock_inference_profiles = [
    "arn:aws:bedrock:*:*:inference-profile/${local.region_prefix}.anthropic.claude-sonnet-4-20250514-v1:0",
    "arn:aws:bedrock:*:*:inference-profile/${local.region_prefix}.anthropic.claude-3-7-sonnet-20250219-v1:0"
  ]
  
  # Combine all Bedrock resources
  bedrock_resources = concat(local.bedrock_foundation_models, local.bedrock_inference_profiles)
}

resource "aws_iam_role_policy" "event_processor_bedrock" {
  name = "${var.name_prefix}-event-processor-bedrock"
  role = aws_iam_role.event_processor_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = local.bedrock_resources
      }
    ]
  })
}

resource "aws_iam_role_policy" "event_processor_health" {
  name = "${var.name_prefix}-event-processor-health"
  role = aws_iam_role.event_processor_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "health:DescribeEvents",
          "health:DescribeEventsForOrganization",
          "health:DescribeEventDetails",
          "health:DescribeEventDetailsForOrganization",
          "health:DescribeAffectedEntities",
          "health:DescribeAffectedEntitiesForOrganization",
          "health:DescribeAffectedAccountsForOrganization",
          "health:DescribeEventAggregates",
          "organizations:ListAccounts",
          "organizations:DescribeOrganization",
          "organizations:DescribeAccount",
          "ses:SendEmail",
          "ses:SendRawEmail",
          "s3:PutObject",
          "s3:GetObject",
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# SQS permissions for parallel event processing
resource "aws_iam_role_policy" "event_processor_sqs" {
  name = "${var.name_prefix}-event-processor-sqs"
  role = aws_iam_role.event_processor_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = [
          "arn:aws:sqs:*:*:${var.name_prefix}-event-processing-queue",
          "arn:aws:sqs:*:*:${var.name_prefix}-event-processing-dlq"
        ]
      }
    ]
  })
}

# Note: Cross-region Lambda permissions are now created in the main.tf after Lambda function creation
# to avoid dependency issues with for_each and computed values


# Email Processor Lambda role
resource "aws_iam_role" "email_processor_role" {
  count = var.enable_email_notifications ? 1 : 0
  
  name = "${var.name_prefix}-email-processor-role"
  tags = var.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "email_processor_basic" {
  count = var.enable_email_notifications ? 1 : 0
  
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.email_processor_role[0].name
}

resource "aws_iam_role_policy" "email_processor_dynamodb" {
  count = var.enable_email_notifications ? 1 : 0
  
  name = "${var.name_prefix}-email-processor-dynamodb"
  role = aws_iam_role.email_processor_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:GetItem"
        ]
        Resource = [
          var.events_table_arn,
          "${var.events_table_arn}/index/*",
          var.account_email_mappings_table_arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "email_processor_ses" {
  count = var.enable_email_notifications ? 1 : 0
  
  name = "${var.name_prefix}-email-processor-ses"
  role = aws_iam_role.email_processor_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "email_processor_s3" {
  count = var.enable_email_notifications ? 1 : 0
  
  name = "${var.name_prefix}-email-processor-s3"
  role = aws_iam_role.email_processor_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::${var.s3_bucket_name}/${var.s3_attachments_prefix}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "email_processor_organizations" {
  count = var.enable_email_notifications ? 1 : 0
  
  name = "${var.name_prefix}-email-processor-organizations"
  role = aws_iam_role.email_processor_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "organizations:ListAccounts",
          "organizations:DescribeAccount"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "email_processor_sqs" {
  count = var.enable_email_notifications ? 1 : 0
  
  name = "${var.name_prefix}-email-processor-sqs"
  role = aws_iam_role.email_processor_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = var.account_email_queue_arn
      }
    ]
  })
}

# Account Email Sender Lambda role
resource "aws_iam_role" "account_email_sender_role" {
  count = var.enable_email_notifications ? 1 : 0
  
  name = "${var.name_prefix}-account-email-sender-role"
  tags = var.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "account_email_sender_basic" {
  count = var.enable_email_notifications ? 1 : 0
  
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.account_email_sender_role[0].name
}

resource "aws_iam_role_policy" "account_email_sender_ses" {
  count = var.enable_email_notifications ? 1 : 0
  
  name = "${var.name_prefix}-account-email-sender-ses"
  role = aws_iam_role.account_email_sender_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "account_email_sender_s3" {
  count = var.enable_email_notifications ? 1 : 0
  
  name = "${var.name_prefix}-account-email-sender-s3"
  role = aws_iam_role.account_email_sender_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "arn:aws:s3:::${var.s3_bucket_name}/${var.s3_attachments_prefix}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "account_email_sender_sqs" {
  count = var.enable_email_notifications ? 1 : 0
  
  name = "${var.name_prefix}-account-email-sender-sqs"
  role = aws_iam_role.account_email_sender_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:ChangeMessageVisibility",
          "sqs:GetQueueAttributes"
        ]
        Resource = var.account_email_queue_arn
      }
    ]
  })
}
