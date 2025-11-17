# Lambda Functions
resource "aws_lambda_function" "dashboard" {
  filename         = data.archive_file.dashboard_zip.output_path
  function_name    = "${var.name_prefix}-dashboard-api"
  role            = var.dashboard_role_arn
  handler         = "index.handler"
  runtime         = "python3.11"
  timeout         = 300
  source_code_hash = data.archive_file.dashboard_zip.output_base64sha256

  environment {
    variables = {
      STAGE = var.stage_name
      DYNAMODB_TABLE = var.counts_table_name
      DYNAMODB_FILTERS_TABLE = var.filters_table_name
      LOG_LEVEL = "INFO"
    }
  }

  tags = var.common_tags
}

resource "aws_lambda_function" "events" {
  filename         = data.archive_file.events_zip.output_path
  function_name    = "${var.name_prefix}-events-api"
  role            = var.events_role_arn
  handler         = "index.handler"
  runtime         = "python3.11"
  timeout         = 30
  source_code_hash = data.archive_file.events_zip.output_base64sha256

  environment {
    variables = {
      STAGE = var.stage_name
      DYNAMODB_HEALTH_EVENTS_TABLE_NAME = var.events_table_name
      FILTERS_FUNCTION_NAME = "${var.name_prefix}-filters-api"
      LOG_LEVEL = "INFO"
    }
  }

  tags = var.common_tags
}

resource "aws_lambda_function" "filters" {
  filename         = data.archive_file.filters_zip.output_path
  function_name    = "${var.name_prefix}-filters-api"
  role            = var.filters_role_arn
  handler         = "index.handler"
  runtime         = "python3.11"
  timeout         = 60
  source_code_hash = data.archive_file.filters_zip.output_base64sha256

  environment {
    variables = {
      STAGE = var.stage_name
      DYNAMODB_TABLE = var.filters_table_name
      LOG_LEVEL = "INFO"
    }
  }

  tags = var.common_tags
}

resource "aws_lambda_function" "event_processor" {
  filename         = data.archive_file.event_processor_zip.output_path
  function_name    = "${var.name_prefix}-event-processor"
  role            = var.event_processor_role_arn
  handler         = "index.handler"
  runtime         = "python3.11"
  timeout         = 900
  source_code_hash = data.archive_file.event_processor_zip.output_base64sha256
  layers           = [aws_lambda_layer_version.python_deps.arn]
  


  environment {
    variables = {
      ANALYSIS_WINDOW_DAYS = "90"
      BEDROCK_MAX_TOKENS = "1000"
      BEDROCK_MODEL_ID = var.bedrock_model_id
      BEDROCK_TEMPERATURE = "0.3"
      EVENTS_TABLE_TTL_DAYS = var.events_table_ttl_days
      DYNAMODB_HEALTH_EVENTS_TABLE_NAME = var.events_table_name
      DYNAMODB_COUNTS_TABLE_NAME = var.counts_table_name
      EVENT_CATEGORIES = "accountNotification,scheduledChange,issue"
      SQS_EVENT_PROCESSING_QUEUE_URL = var.sqs_queue_url
      LOG_LEVEL = "INFO"
    }
  }

  tags = var.common_tags
}

# DynamoDB Stream Event Source Mapping for TTL deletions
resource "aws_lambda_event_source_mapping" "events_stream" {
  event_source_arn  = var.events_table_stream_arn
  function_name     = aws_lambda_function.event_processor.arn
  starting_position = "LATEST"
  
  # Configure batch settings for stream processing
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  parallelization_factor            = 1
  
  # Error handling
  maximum_retry_attempts = 3
  
  # Only process REMOVE events (TTL deletions)
  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["REMOVE"]
      })
    }
  }

  depends_on = [aws_lambda_function.event_processor]
}

# Lambda ZIP files
data "archive_file" "dashboard_zip" {
  type        = "zip"
  source_dir  = "${path.module}/code/dashboard-api"
  output_path = "${path.module}/code/dashboard-api.zip"
}

data "archive_file" "events_zip" {
  type        = "zip"
  source_dir  = "${path.module}/code/events-api"
  output_path = "${path.module}/code/events-api.zip"
}

data "archive_file" "filters_zip" {
  type        = "zip"
  source_dir  = "${path.module}/code/filters-api"
  output_path = "${path.module}/code/filters-api.zip"
}

data "archive_file" "event_processor_zip" {
  type        = "zip"
  source_dir  = "${path.module}/code/event-processor"
  output_path = "${path.module}/code/event-processor.zip"
}

data "archive_file" "email_processor_zip" {
  count       = var.enable_email_notifications ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/code/email-processor"
  output_path = "${path.module}/code/email-processor.zip"
}

# Lambda Layer
resource "aws_lambda_layer_version" "python_deps" {
  filename         = data.archive_file.python_deps_zip.output_path
  layer_name       = "${var.name_prefix}-python-deps"
  source_code_hash = data.archive_file.python_deps_zip.output_base64sha256
  
  compatible_runtimes = ["python3.11"]
  description         = "Python dependencies for event processor"
}

data "archive_file" "python_deps_zip" {
  type        = "zip"
  source_dir  = "${path.module}/layers/python-deps"
  output_path = "${path.module}/layers/python-deps.zip"
  depends_on  = [null_resource.build_layer]
}

resource "null_resource" "build_layer" {
  provisioner "local-exec" {
    command     = "./build.sh"
    working_dir = "${path.module}/layers/python-deps"
  }
  
  triggers = {
    requirements = filemd5("${path.module}/layers/python-deps/requirements.txt")
  }
}

# Email Processor Lambda Layer
resource "aws_lambda_layer_version" "email_processor_deps" {
  count            = var.enable_email_notifications ? 1 : 0
  filename         = data.archive_file.email_processor_deps_zip[0].output_path
  layer_name       = "${var.name_prefix}-email-processor-deps"
  source_code_hash = data.archive_file.email_processor_deps_zip[0].output_base64sha256
  
  compatible_runtimes = ["python3.11"]
  description         = "Python dependencies for email processor"
}

data "archive_file" "email_processor_deps_zip" {
  count       = var.enable_email_notifications ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/layers/email-processor-deps"
  output_path = "${path.module}/layers/email-processor-deps.zip"
  depends_on  = [null_resource.build_email_processor_layer]
}

resource "null_resource" "build_email_processor_layer" {
  count = var.enable_email_notifications ? 1 : 0
  
  provisioner "local-exec" {
    command     = "./build.sh"
    working_dir = "${path.module}/layers/email-processor-deps"
  }
  
  triggers = {
    requirements = filemd5("${path.module}/layers/email-processor-deps/requirements.txt")
  }
}

# Email Processor Lambda Function
resource "aws_lambda_function" "email_processor" {
  count            = var.enable_email_notifications ? 1 : 0
  filename         = data.archive_file.email_processor_zip[0].output_path
  function_name    = "${var.name_prefix}-email-processor"
  role            = var.email_processor_role_arn
  handler         = "index.lambda_handler"
  runtime         = "python3.11"
  timeout         = 900
  source_code_hash = data.archive_file.email_processor_zip[0].output_base64sha256
  layers           = [aws_lambda_layer_version.email_processor_deps[0].arn]

  environment {
    variables = {
      DYNAMODB_HEALTH_EVENTS_TABLE_NAME = var.events_table_name
      SENDER_EMAIL                      = var.sender_email
      MASTER_RECIPIENT_EMAIL            = var.master_recipient_email
      S3_BUCKET_NAME                    = var.s3_bucket_name
      S3_ATTACHMENTS_PREFIX             = "email-attachments"
      PRESIGNED_URL_EXPIRATION          = "604800"  # 7 days
      ACCOUNT_EMAIL_MAPPINGS_TABLE      = var.account_email_mappings_table_name
      ACCOUNT_EMAIL_QUEUE_URL           = var.account_email_queue_url
      ENABLE_PER_ACCOUNT_EMAILS         = var.enable_per_account_emails
      LOG_LEVEL                         = "INFO"
    }
  }

  tags = var.common_tags
}

# Account Email Sender Lambda Function
data "archive_file" "account_email_sender_zip" {
  count       = var.enable_email_notifications ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/code/account-email-sender"
  output_path = "${path.module}/code/account-email-sender.zip"
}

resource "aws_lambda_function" "account_email_sender" {
  count            = var.enable_email_notifications ? 1 : 0
  filename         = data.archive_file.account_email_sender_zip[0].output_path
  function_name    = "${var.name_prefix}-account-email-sender"
  role            = var.account_email_sender_role_arn
  handler         = "index.lambda_handler"
  runtime         = "python3.11"
  timeout         = 300
  memory_size      = 512
  source_code_hash = data.archive_file.account_email_sender_zip[0].output_base64sha256
  layers           = [aws_lambda_layer_version.email_processor_deps[0].arn]
  
  reserved_concurrent_executions = var.account_email_sender_concurrency

  environment {
    variables = {
      S3_BUCKET_NAME                    = var.s3_bucket_name
      S3_ATTACHMENTS_PREFIX             = "email-attachments/account-emails"
      SENDER_EMAIL                      = var.sender_email
      ACCOUNT_EMAIL_CC                  = var.account_email_cc
      PRESIGNED_URL_EXPIRATION          = "604800"  # 7 days
      EMAIL_ATTACHMENT_SIZE_THRESHOLD_MB = "5"
      LOG_LEVEL                         = "INFO"
    }
  }

  tags = var.common_tags
}

# SQS Event Source Mapping for Account Email Sender
resource "aws_lambda_event_source_mapping" "account_email_queue" {
  count            = var.enable_email_notifications ? 1 : 0
  event_source_arn = var.account_email_queue_arn
  function_name    = aws_lambda_function.account_email_sender[0].arn
  batch_size       = 5
  maximum_batching_window_in_seconds = 10
  
  function_response_types = ["ReportBatchItemFailures"]
  
  depends_on = [aws_lambda_function.account_email_sender]
}

