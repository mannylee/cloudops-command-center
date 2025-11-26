# Data source for current region
data "aws_region" "current" {}

# API Gateway
resource "aws_api_gateway_rest_api" "health_dashboard" {
  name        = "${var.name_prefix}-api"
  description = "API for AWS Health Dashboard - Organization Summary"
  tags        = var.common_tags

  body = templatefile("${path.module}/../../aws-health-dashboard-api.yaml", {
    dashboard_function_arn = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${var.dashboard_function_arn}/invocations"
    events_function_arn    = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${var.events_function_arn}/invocations"
    filters_function_arn   = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${var.filters_function_arn}/invocations"
    cognito_user_pool_arn  = var.cognito_user_pool_arn
    name_prefix            = var.name_prefix
  })

  depends_on = [var.dashboard_function_arn, var.events_function_arn, var.filters_function_arn]

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}



# API Gateway Deployment
resource "aws_api_gateway_deployment" "health_dashboard" {
  depends_on = [aws_api_gateway_rest_api.health_dashboard]

  rest_api_id = aws_api_gateway_rest_api.health_dashboard.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.health_dashboard.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}



# API Gateway Stage
resource "aws_api_gateway_stage" "health_dashboard" {
  deployment_id = aws_api_gateway_deployment.health_dashboard.id
  rest_api_id   = aws_api_gateway_rest_api.health_dashboard.id
  stage_name    = var.stage_name
  tags          = var.common_tags
}

# Lambda permissions for API Gateway
resource "aws_lambda_permission" "dashboard_api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = var.dashboard_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.health_dashboard.execution_arn}/*/*"
}

resource "aws_lambda_permission" "events_api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = var.events_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.health_dashboard.execution_arn}/*/*"
}

resource "aws_lambda_permission" "filters_api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = var.filters_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.health_dashboard.execution_arn}/*/*"
}