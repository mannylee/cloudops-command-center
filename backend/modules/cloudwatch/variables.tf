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

variable "event_processor_function_name" {
  description = "Event processor Lambda function name"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

variable "name_prefix" {
  description = "Name prefix for resources"
  type        = string
}

variable "common_tags" {
  description = "Common tags for resources"
  type        = map(string)
  default     = {}
}