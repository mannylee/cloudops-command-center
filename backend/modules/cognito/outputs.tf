output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.health_dashboard.id
}

output "user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.health_dashboard.arn
}

output "user_pool_client_id" {
  description = "Cognito User Pool Client ID for React app"
  value       = aws_cognito_user_pool_client.react_app.id
}

output "user_pool_domain" {
  description = "Cognito User Pool Domain"
  value       = aws_cognito_user_pool_domain.health_dashboard.domain
}

output "cognito_domain_url" {
  description = "Full Cognito domain URL for authentication"
  value       = "https://${aws_cognito_user_pool_domain.health_dashboard.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
}

data "aws_region" "current" {}