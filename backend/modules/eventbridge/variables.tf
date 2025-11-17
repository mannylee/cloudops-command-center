variable "sqs_queue_arn" {
  description = "SQS queue ARN for event processing (used only in deployment region)"
  type        = string
}

variable "deployment_region" {
  description = "The deployment region where SQS queue is located"
  type        = string
}

variable "current_region" {
  description = "Current region where this EventBridge rule is being created"
  type        = string
}

variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "eventbridge_role_arn" {
  description = "IAM role ARN for cross-region EventBridge forwarding"
  type        = string
  default     = ""
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