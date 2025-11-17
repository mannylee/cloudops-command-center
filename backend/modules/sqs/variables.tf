variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "account_email_queue_visibility_timeout" {
  description = "SQS visibility timeout in seconds for account email queue"
  type        = number
  default     = 300
}

