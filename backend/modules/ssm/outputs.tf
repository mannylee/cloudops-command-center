output "parameter_names" {
  description = "List of SSM parameter names created"
  value = concat(
    length(aws_ssm_parameter.api_gateway_url) > 0 ? [aws_ssm_parameter.api_gateway_url[0].name] : [],
    length(aws_ssm_parameter.cognito_user_pool_id) > 0 ? [aws_ssm_parameter.cognito_user_pool_id[0].name] : [],
    length(aws_ssm_parameter.cognito_client_id) > 0 ? [aws_ssm_parameter.cognito_client_id[0].name] : [],
    length(aws_ssm_parameter.cognito_domain_url) > 0 ? [aws_ssm_parameter.cognito_domain_url[0].name] : [],
    [
      aws_ssm_parameter.s3_backend_bucket.name,
      aws_ssm_parameter.dynamodb_backend_table.name,
      aws_ssm_parameter.aws_region.name
    ]
  )
}

output "parameter_arns" {
  description = "List of SSM parameter ARNs created"
  value = concat(
    length(aws_ssm_parameter.api_gateway_url) > 0 ? [aws_ssm_parameter.api_gateway_url[0].arn] : [],
    length(aws_ssm_parameter.cognito_user_pool_id) > 0 ? [aws_ssm_parameter.cognito_user_pool_id[0].arn] : [],
    length(aws_ssm_parameter.cognito_client_id) > 0 ? [aws_ssm_parameter.cognito_client_id[0].arn] : [],
    length(aws_ssm_parameter.cognito_domain_url) > 0 ? [aws_ssm_parameter.cognito_domain_url[0].arn] : [],
    [
      aws_ssm_parameter.s3_backend_bucket.arn,
      aws_ssm_parameter.dynamodb_backend_table.arn,
      aws_ssm_parameter.aws_region.arn
    ]
  )
}