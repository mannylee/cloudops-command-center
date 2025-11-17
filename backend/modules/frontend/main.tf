# S3 bucket for hosting React SPA
resource "aws_s3_bucket" "frontend" {
  bucket        = var.backend_random_suffix != "" ? "${var.name_prefix}-frontend-${var.backend_random_suffix}" : "${var.name_prefix}-frontend"
  force_destroy = true
  tags          = var.common_tags
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Lifecycle Configuration for email attachments
resource "aws_s3_bucket_lifecycle_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    id     = "delete-old-email-attachments"
    status = "Enabled"

    filter {
      prefix = "email-attachments/"
    }

    expiration {
      days = 365  # 12 months
    }
  }
}

# CloudFront Origin Access Control (only if frontend is enabled)
resource "aws_cloudfront_origin_access_control" "frontend" {
  count = var.build_and_upload ? 1 : 0
  
  name                              = var.backend_random_suffix != "" ? "${var.name_prefix}-frontend-oac-${var.backend_random_suffix}" : "${var.name_prefix}-frontend-oac"
  description                       = "OAC for ${var.name_prefix} frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront Distribution (only if frontend is enabled)
resource "aws_cloudfront_distribution" "frontend" {
  count = var.build_and_upload ? 1 : 0
  
  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend[0].id
    origin_id                = "S3-${aws_s3_bucket.frontend.bucket}"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "${var.name_prefix} React SPA"

  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.frontend.bucket}"
    compress               = true
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  # SPA routing - redirect all 404s to index.html
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = var.common_tags
}

# S3 bucket policy for CloudFront access (only if frontend is enabled)
resource "aws_s3_bucket_policy" "frontend" {
  count  = var.build_and_upload ? 1 : 0
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend[0].arn
          }
        }
      }
    ]
  })
}

# Generate aws-exports.json configuration
resource "local_file" "aws_exports" {
  count = var.build_and_upload ? 1 : 0
  
  filename = "${var.frontend_source_path}/public/aws-exports.json"
  content = jsonencode({
    region = var.aws_region
    Auth = {
      Cognito = {
        userPoolClientId = var.cognito_client_id
        userPoolId       = var.cognito_user_pool_id
      }
    }
    API = {
      REST = {
        RestApi = {
          endpoint = var.api_gateway_url
        }
      }
    }
  })
}

# Build and upload React app
resource "null_resource" "build_and_upload" {
  count = var.build_and_upload ? 1 : 0

  triggers = {
    always_run = uuid()
  }

  provisioner "local-exec" {
    command = <<-EOT
      cd ${var.frontend_source_path}
      npm ci
      npm run build
      aws s3 sync dist/ s3://${aws_s3_bucket.frontend.bucket}/ --delete
      aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.frontend[0].id} --paths "/*"
    EOT
  }

  depends_on = [aws_s3_bucket.frontend, aws_cloudfront_distribution.frontend, local_file.aws_exports]
}