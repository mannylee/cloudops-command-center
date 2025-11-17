output "parameter_names" {
  description = "List of SSM parameter names created"
  value = [
    aws_ssm_parameter.api_gateway_url.name,
    aws_ssm_parameter.cognito_user_pool_id.name,
    aws_ssm_parameter.cognito_client_id.name,
    aws_ssm_parameter.cognito_domain_url.name,
    aws_ssm_parameter.s3_backend_bucket.name,
    aws_ssm_parameter.dynamodb_backend_table.name,
    aws_ssm_parameter.aws_region.name
  ]
}

output "parameter_arns" {
  description = "List of SSM parameter ARNs created"
  value = [
    aws_ssm_parameter.api_gateway_url.arn,
    aws_ssm_parameter.cognito_user_pool_id.arn,
    aws_ssm_parameter.cognito_client_id.arn,
    aws_ssm_parameter.cognito_domain_url.arn,
    aws_ssm_parameter.s3_backend_bucket.arn,
    aws_ssm_parameter.dynamodb_backend_table.arn,
    aws_ssm_parameter.aws_region.arn
  ]
}