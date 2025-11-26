variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_profile" {
  description = "AWS profile to use for deployment"
  type        = string
  default     = "default"
}

variable "stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "dev"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "development"
}

variable "react_app_domain" {
  description = "React app domain for Cognito callbacks"
  type        = string
  default     = "localhost:3000"
}



variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "health-dashboard"
}

variable "naming_convention" {
  description = "Naming convention configuration"
  type = object({
    prefix            = optional(string, "")
    suffix            = optional(string, "")
    separator         = optional(string, "-")
    use_random_suffix = optional(bool, false)
  })
  default = {
    prefix            = ""
    suffix            = ""
    separator         = "-"
    use_random_suffix = false
  }
}

variable "s3_backend_bucket" {
  description = "S3 bucket name for Terraform backend"
  type        = string
  default     = ""
}

variable "dynamodb_backend_table" {
  description = "DynamoDB table name for Terraform backend locks"
  type        = string
  default     = ""
}

variable "health_monitoring_regions" {
  description = "List of AWS regions to monitor for health events"
  type        = list(string)
  default     = ["us-east-1"]
}

variable "build_and_upload" {
  description = "Whether to build and upload the React frontend"
  type        = bool
  default     = false
}

variable "frontend_source_path" {
  description = "Path to the frontend source code relative to the Terraform working directory"
  type        = string
  default     = "../../frontend/app"
}

variable "backend_random_suffix" {
  description = "Random suffix from backend setup for consistent naming"
  type        = string
  default     = ""
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
  validation {
    condition     = contains([60, 90, 180], var.events_table_ttl_days)
    error_message = "TTL days must be one of: 60, 90, or 180."
  }
}

variable "enable_email_notifications" {
  description = "Enable email notification functionality"
  type        = bool
  default     = false
}

variable "sender_email" {
  description = "Verified SES sender email address (required if email notifications enabled)"
  type        = string
  default     = ""
}

variable "master_recipient_email" {
  description = "Master recipient email for all health event summaries (required if email notifications enabled)"
  type        = string
  default     = ""
}

variable "email_schedule_expression" {
  description = "EventBridge schedule expression for email reports (default: Monday 9 AM UTC+8 = Monday 1 AM UTC)"
  type        = string
  default     = "cron(0 1 ? * MON *)"
}

variable "enable_per_account_emails" {
  description = "Enable per-account email notifications"
  type        = bool
  default     = true
}

variable "account_email_sender_concurrency" {
  description = "Reserved concurrency for account email sender Lambda"
  type        = number
  default     = 10
}

variable "account_email_queue_visibility_timeout" {
  description = "SQS visibility timeout in seconds for account email queue"
  type        = number
  default     = 300
}

variable "create_account_mappings_table" {
  description = "Create DynamoDB table for custom account email mappings"
  type        = bool
  default     = true
}

variable "account_email_cc" {
  description = "Optional CC email address for all account-specific emails (leave empty to disable)"
  type        = string
  default     = ""
}

variable "event_sync_schedule_expression" {
  description = "EventBridge schedule expression for event sync (default: every 6 hours)"
  type        = string
  default     = "rate(6 hours)"
}

variable "event_sync_lookback_days" {
  description = "Number of days to look back when syncing events"
  type        = number
  default     = 30
}
