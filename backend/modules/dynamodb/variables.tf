variable "environment" {
  description = "Environment name"
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

variable "events_table_ttl_days" {
  description = "Number of days to retain events in DynamoDB before automatic deletion"
  type        = number
  default     = 180
}

variable "create_account_mappings_table" {
  description = "Create DynamoDB table for custom account email mappings"
  type        = bool
  default     = true
}