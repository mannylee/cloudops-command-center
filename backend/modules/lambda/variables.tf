variable "dashboard_role_arn" {
  description = "Dashboard Lambda role ARN"
  type        = string
}

variable "events_role_arn" {
  description = "Events Lambda role ARN"
  type        = string
}

variable "filters_role_arn" {
  description = "Filters Lambda role ARN"
  type        = string
}

variable "event_processor_role_arn" {
  description = "Event Processor Lambda role ARN"
  type        = string
}

variable "stage_name" {
  description = "API Gateway stage name"
  type        = string
}

variable "filters_table_name" {
  description = "DynamoDB filters table name"
  type        = string
}

variable "events_table_name" {
  description = "DynamoDB events table name"
  type        = string
}

variable "counts_table_name" {
  description = "DynamoDB counts table name"
  type        = string
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

variable "sqs_queue_url" {
  description = "SQS queue URL for event processing"
  type        = string
}

variable "events_table_stream_arn" {
  description = "DynamoDB events table stream ARN for TTL processing"
  type        = string
}

variable "bedrock_model_id" {
  description = "Bedrock model ID for AWS Health event analysis"
  type        = string
  default     = "us.anthropic.claude-sonnet-4-20250514-v1:0"
}

variable "events_table_ttl_days" {
  description = "Number of days to retain events in DynamoDB before automatic deletion"
  type        = number
  default     = 180
}

variable "enable_email_notifications" {
  description = "Enable email notification functionality"
  type        = bool
  default     = false
}

variable "email_processor_role_arn" {
  description = "Email Processor Lambda role ARN"
  type        = string
  default     = ""
}

variable "sender_email" {
  description = "Verified SES sender email address"
  type        = string
  default     = ""
}

variable "master_recipient_email" {
  description = "Master recipient email for all health event summaries"
  type        = string
  default     = ""
}

variable "s3_bucket_name" {
  description = "S3 bucket name for email attachments"
  type        = string
  default     = ""
}

variable "account_email_sender_role_arn" {
  description = "Account Email Sender Lambda role ARN"
  type        = string
  default     = ""
}

variable "account_email_queue_arn" {
  description = "SQS queue ARN for account email processing"
  type        = string
  default     = ""
}

variable "account_email_sender_concurrency" {
  description = "Reserved concurrency for account email sender Lambda"
  type        = number
  default     = 10
}

variable "account_email_cc" {
  description = "Optional CC email address for all account-specific emails"
  type        = string
  default     = ""
}

variable "account_email_mappings_table_name" {
  description = "DynamoDB table name for account email mappings"
  type        = string
  default     = ""
}

variable "account_email_queue_url" {
  description = "SQS queue URL for account email processing"
  type        = string
  default     = ""
}

variable "enable_per_account_emails" {
  description = "Enable per-account email notifications"
  type        = bool
  default     = true
}