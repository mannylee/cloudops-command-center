variable "name_prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
}

variable "enable_email_notifications" {
  description = "Enable email notification functionality"
  type        = bool
  default     = false
}

variable "email_schedule_expression" {
  description = "EventBridge schedule expression for email reports (default: Monday 9 AM UTC+8 = Monday 1 AM UTC)"
  type        = string
  default     = "cron(0 1 ? * MON *)"
}
