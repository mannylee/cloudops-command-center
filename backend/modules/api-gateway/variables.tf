variable "stage_name" {
  description = "API Gateway stage name"
  type        = string
}

variable "dashboard_function_arn" {
  description = "Dashboard Lambda function ARN"
  type        = string
}

variable "events_function_arn" {
  description = "Events Lambda function ARN"
  type        = string
}

variable "filters_function_arn" {
  description = "Filters Lambda function ARN"
  type        = string
}

variable "dashboard_function_name" {
  description = "Dashboard Lambda function name"
  type        = string
}

variable "events_function_name" {
  description = "Events Lambda function name"
  type        = string
}

variable "filters_function_name" {
  description = "Filters Lambda function name"
  type        = string
}

variable "name_prefix" {
  description = "Name prefix for resources"
  type        = string
  default     = "health-dashboard"
}

variable "common_tags" {
  description = "Common tags for resources"
  type        = map(string)
  default     = {}
}

variable "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN for authorization"
  type        = string
}

