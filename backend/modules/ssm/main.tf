# SSM Parameters for application configuration

# API Gateway URL (only created if frontend is enabled)
resource "aws_ssm_parameter" "api_gateway_url" {
  count = var.create_frontend_params ? 1 : 0

  name  = "/${var.name_prefix}/api-gateway/url"
  type  = "String"
  value = var.api_gateway_url

  description = "API Gateway endpoint URL for Health Dashboard"
  tags        = var.common_tags
}

# Cognito User Pool ID (only created if frontend is enabled)
resource "aws_ssm_parameter" "cognito_user_pool_id" {
  count = var.create_frontend_params ? 1 : 0

  name  = "/${var.name_prefix}/cognito/user-pool-id"
  type  = "String"
  value = var.cognito_user_pool_id

  description = "Cognito User Pool ID for Health Dashboard"
  tags        = var.common_tags
}

# Cognito User Pool Client ID (only created if frontend is enabled)
resource "aws_ssm_parameter" "cognito_client_id" {
  count = var.create_frontend_params ? 1 : 0

  name  = "/${var.name_prefix}/cognito/client-id"
  type  = "String"
  value = var.cognito_client_id

  description = "Cognito User Pool Client ID for Health Dashboard"
  tags        = var.common_tags
}

# Cognito Domain URL (only created if frontend is enabled)
resource "aws_ssm_parameter" "cognito_domain_url" {
  count = var.create_frontend_params ? 1 : 0

  name  = "/${var.name_prefix}/cognito/domain-url"
  type  = "String"
  value = var.cognito_domain_url

  description = "Cognito Domain URL for Health Dashboard"
  tags        = var.common_tags
}

# S3 Backend Bucket
resource "aws_ssm_parameter" "s3_backend_bucket" {
  name  = "/${var.name_prefix}/backend/s3-bucket"
  type  = "String"
  value = var.s3_backend_bucket

  description = "S3 bucket name for Terraform backend state"
  tags        = var.common_tags
}

# DynamoDB Backend Table
resource "aws_ssm_parameter" "dynamodb_backend_table" {
  name  = "/${var.name_prefix}/backend/dynamodb-table"
  type  = "String"
  value = var.dynamodb_backend_table

  description = "DynamoDB table name for Terraform backend locks"
  tags        = var.common_tags
}

# AWS Region
resource "aws_ssm_parameter" "aws_region" {
  name  = "/${var.name_prefix}/config/aws-region"
  type  = "String"
  value = var.aws_region

  description = "AWS region for Health Dashboard deployment"
  tags        = var.common_tags
}