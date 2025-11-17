variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "health-dashboard"
}

variable "domain_name" {
  description = "Domain name for React app callbacks"
  type        = string
  default     = "localhost:3000"
}

variable "common_tags" {
  description = "Common tags for resources"
  type        = map(string)
  default     = {}
}