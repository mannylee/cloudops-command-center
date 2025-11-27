terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # Backend configuration will be set by deploy.sh
    # bucket, key, region will be configured during deployment
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# Additional providers for multi-region EventBridge deployment
provider "aws" {
  alias   = "us-east-1"
  region  = "us-east-1"
  profile = var.aws_profile
}

provider "aws" {
  alias   = "us-east-2"
  region  = "us-east-2"
  profile = var.aws_profile
}

provider "aws" {
  alias   = "us-west-1"
  region  = "us-west-1"
  profile = var.aws_profile
}

provider "aws" {
  alias   = "us-west-2"
  region  = "us-west-2"
  profile = var.aws_profile
}

provider "aws" {
  alias   = "eu-west-1"
  region  = "eu-west-1"
  profile = var.aws_profile
}

provider "aws" {
  alias   = "eu-west-2"
  region  = "eu-west-2"
  profile = var.aws_profile
}

provider "aws" {
  alias   = "eu-west-3"
  region  = "eu-west-3"
  profile = var.aws_profile
}

provider "aws" {
  alias   = "eu-central-1"
  region  = "eu-central-1"
  profile = var.aws_profile
}

provider "aws" {
  alias   = "eu-north-1"
  region  = "eu-north-1"
  profile = var.aws_profile
}

provider "aws" {
  alias   = "ap-southeast-1"
  region  = "ap-southeast-1"
  profile = var.aws_profile
}

provider "aws" {
  alias   = "ap-southeast-2"
  region  = "ap-southeast-2"
  profile = var.aws_profile
}

provider "aws" {
  alias   = "ap-northeast-1"
  region  = "ap-northeast-1"
  profile = var.aws_profile
}

provider "aws" {
  alias   = "ap-northeast-2"
  region  = "ap-northeast-2"
  profile = var.aws_profile
}

provider "aws" {
  alias   = "ap-northeast-3"
  region  = "ap-northeast-3"
  profile = var.aws_profile
}

provider "aws" {
  alias   = "ap-south-1"
  region  = "ap-south-1"
  profile = var.aws_profile
}

provider "aws" {
  alias   = "ca-central-1"
  region  = "ca-central-1"
  profile = var.aws_profile
}

provider "aws" {
  alias   = "sa-east-1"
  region  = "sa-east-1"
  profile = var.aws_profile
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}



# Naming convention locals
locals {
  # Base naming components
  base_name     = var.project_name
  prefix        = var.naming_convention.prefix != "" ? "${var.naming_convention.prefix}${var.naming_convention.separator}" : ""
  suffix        = var.naming_convention.suffix != "" ? "${var.naming_convention.separator}${var.naming_convention.suffix}" : ""
  random_suffix = var.naming_convention.use_random_suffix ? "${var.naming_convention.separator}${random_id.naming_suffix[0].hex}" : ""

  # Final naming pattern
  name_prefix = "${local.prefix}${local.base_name}${local.suffix}${local.random_suffix}"

  # Common tags to be applied to all resources
  common_tags = {
    Project            = "AWS CloudOps Command Center"
    Environment        = var.environment
    ManagedBy          = "Terraform"
    Repository         = "cloudops-command-center"
    Owner              = var.sender_email != "" ? var.sender_email : "unspecified"
    DeployedAt         = timestamp()
    DataClassification = "Internal"
    auto-delete        = "no"
  }
}

# Random suffix for unique naming (conditional)
resource "random_id" "naming_suffix" {
  count       = var.naming_convention.use_random_suffix ? 1 : 0
  byte_length = 4
}

# Cognito User Pool (only if frontend is enabled)
module "cognito" {
  count  = var.build_and_upload ? 1 : 0
  source = "../modules/cognito"

  environment  = var.environment
  project_name = local.name_prefix
  domain_name  = var.react_app_domain
  common_tags  = local.common_tags
}

# DynamoDB Tables
module "dynamodb" {
  source = "../modules/dynamodb"

  environment                   = var.environment
  name_prefix                   = local.name_prefix
  common_tags                   = local.common_tags
  events_table_ttl_days         = var.events_table_ttl_days
  create_account_mappings_table = var.create_account_mappings_table
}

# SQS Queues for parallel event processing (created first)
module "sqs" {
  source = "../modules/sqs"

  name_prefix                            = local.name_prefix
  common_tags                            = local.common_tags
  account_email_queue_visibility_timeout = var.account_email_queue_visibility_timeout
}

# EventBridge Email Schedule (optional)
module "sns" {
  source = "../modules/sns"

  name_prefix                = local.name_prefix
  common_tags                = local.common_tags
  enable_email_notifications = var.enable_email_notifications
  email_schedule_expression  = var.email_schedule_expression
}

# IAM Roles
module "iam" {
  source = "../modules/iam"

  filters_table_arn                = module.dynamodb.filters_table_arn
  events_table_arn                 = module.dynamodb.events_table_arn
  counts_table_arn                 = module.dynamodb.counts_table_arn
  account_email_mappings_table_arn = module.dynamodb.account_email_mappings_table_arn
  account_email_queue_arn          = module.sqs.account_email_queue_arn
  name_prefix                      = local.name_prefix
  common_tags                      = local.common_tags
  deployment_region                = var.aws_region
  bedrock_model_id                 = var.bedrock_model_id
  enable_email_notifications       = var.enable_email_notifications
  s3_bucket_name                   = module.frontend.s3_bucket_name
  s3_attachments_prefix            = "email-attachments"
}

# Lambda Functions
module "lambda" {
  source = "../modules/lambda"

  dashboard_role_arn                = module.iam.dashboard_role_arn
  events_role_arn                   = module.iam.events_role_arn
  filters_role_arn                  = module.iam.filters_role_arn
  event_processor_role_arn          = module.iam.event_processor_role_arn
  email_processor_role_arn          = module.iam.email_processor_role_arn
  account_email_sender_role_arn     = module.iam.account_email_sender_role_arn
  stage_name                        = var.stage_name
  filters_table_name                = module.dynamodb.filters_table_name
  events_table_name                 = module.dynamodb.events_table_name
  counts_table_name                 = module.dynamodb.counts_table_name
  name_prefix                       = local.name_prefix
  common_tags                       = local.common_tags
  sqs_queue_url                     = module.sqs.event_processing_queue_url
  events_table_stream_arn           = module.dynamodb.events_table_stream_arn
  bedrock_model_id                  = var.bedrock_model_id
  events_table_ttl_days             = var.events_table_ttl_days
  enable_email_notifications        = var.enable_email_notifications
  sender_email                      = var.sender_email
  master_recipient_email            = var.master_recipient_email
  s3_bucket_name                    = module.frontend.s3_bucket_name
  account_email_queue_arn           = module.sqs.account_email_queue_arn
  account_email_sender_concurrency  = var.account_email_sender_concurrency
  account_email_cc                  = var.account_email_cc
  account_email_mappings_table_name = module.dynamodb.account_email_mappings_table_name
  account_email_queue_url           = module.sqs.account_email_queue_url
  enable_per_account_emails         = var.enable_per_account_emails
}

# Lambda Event Source Mapping for SQS (processes health events from EventBridge)
resource "aws_lambda_event_source_mapping" "event_processing_trigger" {
  event_source_arn = module.sqs.event_processing_queue_arn
  function_name    = module.lambda.event_processor_function_name

  # Process messages in batches of 1 for individual processing
  batch_size = 1

  # Set batching window to 10 seconds
  maximum_batching_window_in_seconds = 10

  # Set concurrent lambda instances to 3
  scaling_config {
    maximum_concurrency = 3
  }

  # Configure error handling
  function_response_types = ["ReportBatchItemFailures"]
}

# EventBridge Target for Email Processing Lambda
resource "aws_cloudwatch_event_target" "email_processor" {
  count = var.enable_email_notifications ? 1 : 0

  rule      = module.sns.email_schedule_rule_name
  target_id = "EmailProcessorLambda"
  arn       = module.lambda.email_processor_function_arn
}

# Lambda Permission for EventBridge to invoke Email Processor
resource "aws_lambda_permission" "email_processor_eventbridge" {
  count = var.enable_email_notifications ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda.email_processor_function_name
  principal     = "events.amazonaws.com"
  source_arn    = module.sns.email_schedule_rule_arn
}

# Cross-region Lambda permissions for EventBridge health event monitoring
# These permissions allow EventBridge rules from multiple regions to invoke the event processor Lambda
resource "aws_lambda_permission" "eventbridge_cross_region" {
  for_each = toset(var.health_monitoring_regions)

  statement_id  = "AllowExecutionFromEventBridge-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda.event_processor_function_name
  principal     = "events.amazonaws.com"
  source_arn    = "arn:aws:events:${each.key}:${data.aws_caller_identity.current.account_id}:rule/${local.name_prefix}-${each.key}-*"
}

# EventBridge resource policy to allow cross-region forwarding to deployment region
resource "aws_cloudwatch_event_permission" "cross_region_eventbridge" {
  principal    = data.aws_caller_identity.current.account_id
  statement_id = "AllowCrossRegionEventBridge"
  action       = "events:PutEvents"
}

# SQS permissions for EventBridge (deployment region only)
resource "aws_sqs_queue_policy" "eventbridge_deployment_region" {
  queue_url = module.sqs.event_processing_queue_url

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgeFromDeploymentRegion"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = module.sqs.event_processing_queue_arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          StringLike = {
            "aws:SourceArn" = "arn:aws:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:rule/${local.name_prefix}-${var.aws_region}-*"
          }
        }
      }
    ]
  })
}

# CloudWatch Log Groups
module "cloudwatch" {
  source = "../modules/cloudwatch"

  dashboard_function_name        = module.lambda.dashboard_function_name
  events_function_name           = module.lambda.events_function_name
  filters_function_name          = module.lambda.filters_function_name
  event_processor_function_name  = module.lambda.event_processor_function_name
  event_processor_function_arn   = module.lambda.event_processor_function_arn
  log_retention_days             = 14
  event_sync_schedule_expression = var.event_sync_schedule_expression
  event_sync_lookback_days       = var.event_sync_lookback_days
  name_prefix                    = local.name_prefix
  common_tags                    = local.common_tags
}

# EventBridge rules for health event monitoring across regions
# Create locals to determine which regions to deploy
locals {
  # Create a map of regions that are actually selected
  selected_regions = toset(var.health_monitoring_regions)
}

# Cross-region Lambda permissions are now handled in the IAM module

# EventBridge for us-east-1 when it's the deployment region
module "eventbridge_us_east_1_deployment" {
  count = contains(var.health_monitoring_regions, "us-east-1") && var.aws_region == "us-east-1" ? 1 : 0

  source = "../modules/eventbridge"

  providers = {
    aws = aws
  }

  sqs_queue_arn        = module.sqs.event_processing_queue_arn
  deployment_region    = var.aws_region
  current_region       = "us-east-1"
  account_id           = data.aws_caller_identity.current.account_id
  eventbridge_role_arn = module.iam.eventbridge_cross_region_role_arn
  name_prefix          = "${local.name_prefix}-us-east-1"
  common_tags = merge(local.common_tags, {
    Region = "us-east-1"
  })
}

# EventBridge for us-east-1 when it's NOT the deployment region
module "eventbridge_us_east_1_monitoring" {
  count = contains(var.health_monitoring_regions, "us-east-1") && var.aws_region != "us-east-1" ? 1 : 0

  source = "../modules/eventbridge"

  providers = {
    aws = aws.us-east-1
  }

  sqs_queue_arn        = module.sqs.event_processing_queue_arn
  deployment_region    = var.aws_region
  current_region       = "us-east-1"
  account_id           = data.aws_caller_identity.current.account_id
  eventbridge_role_arn = module.iam.eventbridge_cross_region_role_arn
  name_prefix          = "${local.name_prefix}-us-east-1"
  common_tags = merge(local.common_tags, {
    Region = "us-east-1"
  })
}

# EventBridge for us-east-2
module "eventbridge_us_east_2" {
  count = contains(var.health_monitoring_regions, "us-east-2") ? 1 : 0

  source = "../modules/eventbridge"

  providers = {
    aws = aws.us-east-2
  }

  sqs_queue_arn        = module.sqs.event_processing_queue_arn
  deployment_region    = var.aws_region
  current_region       = "us-east-2"
  account_id           = data.aws_caller_identity.current.account_id
  eventbridge_role_arn = module.iam.eventbridge_cross_region_role_arn
  name_prefix          = "${local.name_prefix}-us-east-2"
  common_tags = merge(local.common_tags, {
    Region = "us-east-2"
  })
}

# EventBridge for us-west-1
module "eventbridge_us_west_1" {
  count = contains(var.health_monitoring_regions, "us-west-1") ? 1 : 0

  source = "../modules/eventbridge"

  providers = {
    aws = aws.us-west-1
  }

  sqs_queue_arn        = module.sqs.event_processing_queue_arn
  deployment_region    = var.aws_region
  current_region       = "us-west-1"
  account_id           = data.aws_caller_identity.current.account_id
  eventbridge_role_arn = module.iam.eventbridge_cross_region_role_arn
  name_prefix          = "${local.name_prefix}-us-west-1"
  common_tags = merge(local.common_tags, {
    Region = "us-west-1"
  })
}

# EventBridge for us-west-2
module "eventbridge_us_west_2" {
  count = contains(var.health_monitoring_regions, "us-west-2") ? 1 : 0

  source = "../modules/eventbridge"

  providers = {
    aws = aws.us-west-2
  }

  sqs_queue_arn        = module.sqs.event_processing_queue_arn
  deployment_region    = var.aws_region
  current_region       = "us-west-2"
  account_id           = data.aws_caller_identity.current.account_id
  eventbridge_role_arn = module.iam.eventbridge_cross_region_role_arn
  name_prefix          = "${local.name_prefix}-us-west-2"
  common_tags = merge(local.common_tags, {
    Region = "us-west-2"
  })
}

# EventBridge for eu-west-1
module "eventbridge_eu_west_1" {
  count = contains(var.health_monitoring_regions, "eu-west-1") ? 1 : 0

  source = "../modules/eventbridge"

  providers = {
    aws = aws.eu-west-1
  }

  sqs_queue_arn        = module.sqs.event_processing_queue_arn
  deployment_region    = var.aws_region
  current_region       = "eu-west-1"
  account_id           = data.aws_caller_identity.current.account_id
  eventbridge_role_arn = module.iam.eventbridge_cross_region_role_arn
  name_prefix          = "${local.name_prefix}-eu-west-1"
  common_tags = merge(local.common_tags, {
    Region = "eu-west-1"
  })
}

# EventBridge for eu-west-2
module "eventbridge_eu_west_2" {
  count = contains(var.health_monitoring_regions, "eu-west-2") ? 1 : 0

  source = "../modules/eventbridge"

  providers = {
    aws = aws.eu-west-2
  }

  sqs_queue_arn        = module.sqs.event_processing_queue_arn
  deployment_region    = var.aws_region
  current_region       = "eu-west-2"
  account_id           = data.aws_caller_identity.current.account_id
  eventbridge_role_arn = module.iam.eventbridge_cross_region_role_arn
  name_prefix          = "${local.name_prefix}-eu-west-2"
  common_tags = merge(local.common_tags, {
    Region = "eu-west-2"
  })
}

# EventBridge for eu-west-3
module "eventbridge_eu_west_3" {
  count = contains(var.health_monitoring_regions, "eu-west-3") ? 1 : 0

  source = "../modules/eventbridge"

  providers = {
    aws = aws.eu-west-3
  }

  sqs_queue_arn        = module.sqs.event_processing_queue_arn
  deployment_region    = var.aws_region
  current_region       = "eu-west-3"
  account_id           = data.aws_caller_identity.current.account_id
  eventbridge_role_arn = module.iam.eventbridge_cross_region_role_arn
  name_prefix          = "${local.name_prefix}-eu-west-3"
  common_tags = merge(local.common_tags, {
    Region = "eu-west-3"
  })
}

# EventBridge for eu-central-1
module "eventbridge_eu_central_1" {
  count = contains(var.health_monitoring_regions, "eu-central-1") ? 1 : 0

  source = "../modules/eventbridge"

  providers = {
    aws = aws.eu-central-1
  }

  sqs_queue_arn        = module.sqs.event_processing_queue_arn
  deployment_region    = var.aws_region
  current_region       = "eu-central-1"
  account_id           = data.aws_caller_identity.current.account_id
  eventbridge_role_arn = module.iam.eventbridge_cross_region_role_arn
  name_prefix          = "${local.name_prefix}-eu-central-1"
  common_tags = merge(local.common_tags, {
    Region = "eu-central-1"
  })
}

# EventBridge for eu-north-1
module "eventbridge_eu_north_1" {
  count = contains(var.health_monitoring_regions, "eu-north-1") ? 1 : 0

  source = "../modules/eventbridge"

  providers = {
    aws = aws.eu-north-1
  }

  sqs_queue_arn        = module.sqs.event_processing_queue_arn
  deployment_region    = var.aws_region
  current_region       = "eu-north-1"
  account_id           = data.aws_caller_identity.current.account_id
  eventbridge_role_arn = module.iam.eventbridge_cross_region_role_arn
  name_prefix          = "${local.name_prefix}-eu-north-1"
  common_tags = merge(local.common_tags, {
    Region = "eu-north-1"
  })
}

# EventBridge for ap-southeast-1
module "eventbridge_ap_southeast_1" {
  count = contains(var.health_monitoring_regions, "ap-southeast-1") ? 1 : 0

  source = "../modules/eventbridge"

  providers = {
    aws = aws.ap-southeast-1
  }

  sqs_queue_arn        = module.sqs.event_processing_queue_arn
  deployment_region    = var.aws_region
  current_region       = "ap-southeast-1"
  account_id           = data.aws_caller_identity.current.account_id
  eventbridge_role_arn = module.iam.eventbridge_cross_region_role_arn
  name_prefix          = "${local.name_prefix}-ap-southeast-1"
  common_tags = merge(local.common_tags, {
    Region = "ap-southeast-1"
  })
}

# EventBridge for ap-southeast-2
module "eventbridge_ap_southeast_2" {
  count = contains(var.health_monitoring_regions, "ap-southeast-2") ? 1 : 0

  source = "../modules/eventbridge"

  providers = {
    aws = aws.ap-southeast-2
  }

  sqs_queue_arn        = module.sqs.event_processing_queue_arn
  deployment_region    = var.aws_region
  current_region       = "ap-southeast-2"
  account_id           = data.aws_caller_identity.current.account_id
  eventbridge_role_arn = module.iam.eventbridge_cross_region_role_arn
  name_prefix          = "${local.name_prefix}-ap-southeast-2"
  common_tags = merge(local.common_tags, {
    Region = "ap-southeast-2"
  })
}

# EventBridge for ap-northeast-1
module "eventbridge_ap_northeast_1" {
  count = contains(var.health_monitoring_regions, "ap-northeast-1") ? 1 : 0

  source = "../modules/eventbridge"

  providers = {
    aws = aws.ap-northeast-1
  }

  sqs_queue_arn        = module.sqs.event_processing_queue_arn
  deployment_region    = var.aws_region
  current_region       = "ap-northeast-1"
  account_id           = data.aws_caller_identity.current.account_id
  eventbridge_role_arn = module.iam.eventbridge_cross_region_role_arn
  name_prefix          = "${local.name_prefix}-ap-northeast-1"
  common_tags = merge(local.common_tags, {
    Region = "ap-northeast-1"
  })
}

# EventBridge for ap-northeast-2
module "eventbridge_ap_northeast_2" {
  count = contains(var.health_monitoring_regions, "ap-northeast-2") ? 1 : 0

  source = "../modules/eventbridge"

  providers = {
    aws = aws.ap-northeast-2
  }

  sqs_queue_arn        = module.sqs.event_processing_queue_arn
  deployment_region    = var.aws_region
  current_region       = "ap-northeast-2"
  account_id           = data.aws_caller_identity.current.account_id
  eventbridge_role_arn = module.iam.eventbridge_cross_region_role_arn
  name_prefix          = "${local.name_prefix}-ap-northeast-2"
  common_tags = merge(local.common_tags, {
    Region = "ap-northeast-2"
  })
}

# EventBridge for ap-northeast-3
module "eventbridge_ap_northeast_3" {
  count = contains(var.health_monitoring_regions, "ap-northeast-3") ? 1 : 0

  source = "../modules/eventbridge"

  providers = {
    aws = aws.ap-northeast-3
  }

  sqs_queue_arn        = module.sqs.event_processing_queue_arn
  deployment_region    = var.aws_region
  current_region       = "ap-northeast-3"
  account_id           = data.aws_caller_identity.current.account_id
  eventbridge_role_arn = module.iam.eventbridge_cross_region_role_arn
  name_prefix          = "${local.name_prefix}-ap-northeast-3"
  common_tags = merge(local.common_tags, {
    Region = "ap-northeast-3"
  })
}

# EventBridge for ap-south-1
module "eventbridge_ap_south_1" {
  count = contains(var.health_monitoring_regions, "ap-south-1") ? 1 : 0

  source = "../modules/eventbridge"

  providers = {
    aws = aws.ap-south-1
  }

  sqs_queue_arn        = module.sqs.event_processing_queue_arn
  deployment_region    = var.aws_region
  current_region       = "ap-south-1"
  account_id           = data.aws_caller_identity.current.account_id
  eventbridge_role_arn = module.iam.eventbridge_cross_region_role_arn
  name_prefix          = "${local.name_prefix}-ap-south-1"
  common_tags = merge(local.common_tags, {
    Region = "ap-south-1"
  })
}

# EventBridge for ca-central-1
module "eventbridge_ca_central_1" {
  count = contains(var.health_monitoring_regions, "ca-central-1") ? 1 : 0

  source = "../modules/eventbridge"

  providers = {
    aws = aws.ca-central-1
  }

  sqs_queue_arn        = module.sqs.event_processing_queue_arn
  deployment_region    = var.aws_region
  current_region       = "ca-central-1"
  account_id           = data.aws_caller_identity.current.account_id
  eventbridge_role_arn = module.iam.eventbridge_cross_region_role_arn
  name_prefix          = "${local.name_prefix}-ca-central-1"
  common_tags = merge(local.common_tags, {
    Region = "ca-central-1"
  })
}

# EventBridge for sa-east-1
module "eventbridge_sa_east_1" {
  count = contains(var.health_monitoring_regions, "sa-east-1") ? 1 : 0

  source = "../modules/eventbridge"

  providers = {
    aws = aws.sa-east-1
  }

  sqs_queue_arn        = module.sqs.event_processing_queue_arn
  deployment_region    = var.aws_region
  current_region       = "sa-east-1"
  account_id           = data.aws_caller_identity.current.account_id
  eventbridge_role_arn = module.iam.eventbridge_cross_region_role_arn
  name_prefix          = "${local.name_prefix}-sa-east-1"
  common_tags = merge(local.common_tags, {
    Region = "sa-east-1"
  })
}

# API Gateway (only if frontend is enabled)
module "api_gateway" {
  count  = var.build_and_upload ? 1 : 0
  source = "../modules/api-gateway"

  stage_name              = var.stage_name
  dashboard_function_arn  = module.lambda.dashboard_function_arn
  events_function_arn     = module.lambda.events_function_arn
  filters_function_arn    = module.lambda.filters_function_arn
  dashboard_function_name = module.lambda.dashboard_function_name
  events_function_name    = module.lambda.events_function_name
  filters_function_name   = module.lambda.filters_function_name
  name_prefix             = local.name_prefix
  common_tags             = local.common_tags
  cognito_user_pool_arn   = module.cognito[0].user_pool_arn
}

# Frontend (S3 + CloudFront)
module "frontend" {
  source = "../modules/frontend"

  name_prefix           = local.name_prefix
  common_tags           = local.common_tags
  build_and_upload      = var.build_and_upload
  frontend_source_path  = var.frontend_source_path
  aws_region            = var.aws_region
  cognito_user_pool_id  = var.build_and_upload ? module.cognito[0].user_pool_id : ""
  cognito_client_id     = var.build_and_upload ? module.cognito[0].user_pool_client_id : ""
  api_gateway_url       = var.build_and_upload ? module.api_gateway[0].api_gateway_url : ""
  backend_random_suffix = var.backend_random_suffix
}

# SSM Parameters
module "ssm" {
  source = "../modules/ssm"

  name_prefix            = local.name_prefix
  common_tags            = local.common_tags
  api_gateway_url        = var.build_and_upload ? module.api_gateway[0].api_gateway_url : ""
  cognito_user_pool_id   = var.build_and_upload ? module.cognito[0].user_pool_id : ""
  cognito_client_id      = var.build_and_upload ? module.cognito[0].user_pool_client_id : ""
  cognito_domain_url     = var.build_and_upload ? module.cognito[0].cognito_domain_url : ""
  s3_backend_bucket      = var.s3_backend_bucket
  dynamodb_backend_table = var.dynamodb_backend_table
  aws_region             = var.aws_region
}