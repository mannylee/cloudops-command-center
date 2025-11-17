variable "name_prefix" {
  description = "Name prefix for resources"
  type        = string
}

variable "common_tags" {
  description = "Common tags for resources"
  type        = map(string)
  default     = {}
}

variable "api_gateway_url" {
  description = "API Gateway endpoint URL"
  type        = string
}

variable "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  type        = string
}

variable "cognito_client_id" {
  description = "Cognito User Pool Client ID"
  type        = string
}

variable "cognito_domain_url" {
  description = "Cognito Domain URL"
  type        = string
}

variable "s3_backend_bucket" {
  description = "S3 backend bucket name"
  type        = string
}

variable "dynamodb_backend_table" {
  description = "DynamoDB backend table name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}