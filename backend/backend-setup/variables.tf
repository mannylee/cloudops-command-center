variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "health-dashboard"
}

variable "aws_profile" {
  description = "AWS profile to use"
  type        = string
  default     = "default"
}

variable "naming_convention" {
  description = "Naming convention configuration"
  type = object({
    prefix    = optional(string, "")
    suffix    = optional(string, "")
    separator = optional(string, "-")
    use_random_suffix = optional(bool, false)
  })
  default = {
    prefix    = ""
    suffix    = ""
    separator = "-"
    use_random_suffix = false
  }
}