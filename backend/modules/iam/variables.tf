variable "filters_table_arn" {
  description = "ARN of the filters DynamoDB table"
  type        = string
}

variable "events_table_arn" {
  description = "ARN of the events DynamoDB table"
  type        = string
}

variable "counts_table_arn" {
  description = "ARN of the counts DynamoDB table"
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

variable "deployment_region" {
  description = "AWS deployment region for region-specific Bedrock permissions"
  type        = string
}

variable "bedrock_model_id" {
  description = "Bedrock model ID for permissions"
  type        = string
}

# Cross-region Lambda permissions variables removed - now handled in main.tf

variable "enable_email_notifications" {
  description = "Enable email notification functionality"
  type        = bool
  default     = false
}

variable "s3_bucket_name" {
  description = "S3 bucket name for email attachments"
  type        = string
  default     = ""
}

variable "s3_attachments_prefix" {
  description = "S3 prefix for email attachments"
  type        = string
  default     = "email-attachments"
}

variable "account_email_mappings_table_arn" {
  description = "ARN of the account email mappings DynamoDB table"
  type        = string
  default     = ""
}

variable "account_email_queue_arn" {
  description = "ARN of the account email SQS queue"
  type        = string
  default     = ""
}