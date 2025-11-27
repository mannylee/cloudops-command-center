terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project            = "AWS CloudOps Command Center"
      ManagedBy          = "Terraform"
      Repository         = "cloudops-command-center"
      Component          = "Backend"
      DataClassification = "Internal"
      "auto-delete"      = "no"
    }
  }
}

# Naming convention locals (same as main infrastructure)
locals {
  # Base naming components
  base_name     = var.project_name
  prefix        = var.naming_convention.prefix != "" ? "${var.naming_convention.prefix}${var.naming_convention.separator}" : ""
  suffix        = var.naming_convention.suffix != "" ? "${var.naming_convention.separator}${var.naming_convention.suffix}" : ""
  random_suffix = var.naming_convention.use_random_suffix ? "${var.naming_convention.separator}${random_id.naming_suffix[0].hex}" : ""

  # Final naming pattern for backend resources
  backend_name_prefix = "${local.prefix}${local.base_name}${local.suffix}${local.random_suffix}-backend"
}

# Random suffix for unique naming (conditional)
resource "random_id" "naming_suffix" {
  count       = var.naming_convention.use_random_suffix ? 1 : 0
  byte_length = 4
}

# S3 bucket for Terraform state
resource "aws_s3_bucket" "terraform_state" {
  bucket        = "${local.backend_name_prefix}-terraform-state-${random_id.bucket_suffix.hex}"
  force_destroy = true
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for state locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${local.backend_name_prefix}-terraform-locks-${random_id.bucket_suffix.hex}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name          = "${local.backend_name_prefix}-terraform-locks"
    "auto-delete" = "no"
  }
}