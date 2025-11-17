variable "name_prefix" {
  description = "Name prefix for resources"
  type        = string
}

variable "common_tags" {
  description = "Common tags for resources"
  type        = map(string)
  default     = {}
}

variable "build_and_upload" {
  description = "Whether to build and upload the React app"
  type        = bool
  default     = false
}

variable "frontend_source_path" {
  description = "Path to the frontend source code"
  type        = string
  default     = "../../../frontend/app"
}

variable "aws_region" {
  description = "AWS region for configuration"
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

variable "api_gateway_url" {
  description = "API Gateway endpoint URL"
  type        = string
}

variable "backend_random_suffix" {
  description = "Random suffix from backend setup for consistent naming"
  type        = string
  default     = ""
}