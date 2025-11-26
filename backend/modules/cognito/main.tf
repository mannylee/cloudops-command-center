# Cognito User Pool
resource "aws_cognito_user_pool" "health_dashboard" {
  name = "${var.project_name}-users"

  # Password policy
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  # User attributes
  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  # Email configuration
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # Account recovery
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-user-pool"
    Environment = var.environment
  })
}

# Cognito User Pool Client (for React app)
resource "aws_cognito_user_pool_client" "react_app" {
  name         = "${var.project_name}-react-app"
  user_pool_id = aws_cognito_user_pool.health_dashboard.id

  # OAuth settings for React SPA
  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]

  # Callback URLs for React app
  callback_urls = [
    "http://localhost:3000/callback",
    "https://${var.domain_name}/callback"
  ]

  logout_urls = [
    "http://localhost:3000",
    "https://${var.domain_name}"
  ]

  # Token validity
  access_token_validity  = 1  # 1 hour
  id_token_validity      = 1  # 1 hour
  refresh_token_validity = 30 # 30 days

  # Prevent user existence errors
  prevent_user_existence_errors = "ENABLED"

  # Explicit auth flows for React and testing
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_ADMIN_USER_PASSWORD_AUTH" # REMOVE THIS - ONLY FOR TESTING PURPOSE WITHOUT FRONTEND
  ]
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "health_dashboard" {
  domain       = "${var.project_name}-${random_id.domain_suffix.hex}"
  user_pool_id = aws_cognito_user_pool.health_dashboard.id
}

resource "random_id" "domain_suffix" {
  byte_length = 4
}