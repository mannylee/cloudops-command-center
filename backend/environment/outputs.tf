output "api_gateway_url" {
  description = "API Gateway endpoint URL"
  value       = length(module.api_gateway) > 0 ? module.api_gateway[0].api_gateway_url : ""
}

output "api_gateway_id" {
  description = "API Gateway ID"
  value       = length(module.api_gateway) > 0 ? module.api_gateway[0].api_gateway_id : ""
}

output "lambda_function_names" {
  description = "Lambda function names"
  value       = module.lambda.function_names
}

output "event_processor_function_name" {
  description = "Event processor Lambda function name"
  value       = module.lambda.event_processor_function_name
}

output "dynamodb_table_names" {
  description = "DynamoDB table names"
  value       = module.dynamodb.table_names
}

output "cognito_config" {
  description = "Cognito configuration for React app"
  value = length(module.cognito) > 0 ? {
    user_pool_id     = module.cognito[0].user_pool_id
    client_id        = module.cognito[0].user_pool_client_id
    domain_url       = module.cognito[0].cognito_domain_url
  } : {
    user_pool_id     = ""
    client_id        = ""
    domain_url       = ""
  }
}

output "health_monitoring_regions" {
  description = "Regions configured for health event monitoring"
  value       = var.health_monitoring_regions
}

output "frontend_config" {
  description = "Frontend hosting configuration"
  value = {
    s3_bucket_name           = module.frontend.s3_bucket_name
    cloudfront_distribution_id = module.frontend.cloudfront_distribution_id
    cloudfront_url           = module.frontend.cloudfront_url
  }
}

output "eventbridge_rules" {
  description = "EventBridge rules deployed across regions"
  value = merge(
    # us-east-1 (deployment region)
    length(module.eventbridge_us_east_1_deployment) > 0 ? {
      "us-east-1" = {
        rule_name = module.eventbridge_us_east_1_deployment[0].rule_name
        rule_arn  = module.eventbridge_us_east_1_deployment[0].rule_arn
        region    = "us-east-1"
      }
    } : {},
    # us-east-1 (monitoring region)
    length(module.eventbridge_us_east_1_monitoring) > 0 ? {
      "us-east-1" = {
        rule_name = module.eventbridge_us_east_1_monitoring[0].rule_name
        rule_arn  = module.eventbridge_us_east_1_monitoring[0].rule_arn
        region    = "us-east-1"
      }
    } : {},
    # us-east-2
    length(module.eventbridge_us_east_2) > 0 ? {
      "us-east-2" = {
        rule_name = module.eventbridge_us_east_2[0].rule_name
        rule_arn  = module.eventbridge_us_east_2[0].rule_arn
        region    = "us-east-2"
      }
    } : {},
    # us-west-1
    length(module.eventbridge_us_west_1) > 0 ? {
      "us-west-1" = {
        rule_name = module.eventbridge_us_west_1[0].rule_name
        rule_arn  = module.eventbridge_us_west_1[0].rule_arn
        region    = "us-west-1"
      }
    } : {},
    # us-west-2
    length(module.eventbridge_us_west_2) > 0 ? {
      "us-west-2" = {
        rule_name = module.eventbridge_us_west_2[0].rule_name
        rule_arn  = module.eventbridge_us_west_2[0].rule_arn
        region    = "us-west-2"
      }
    } : {},
    # eu-west-1
    length(module.eventbridge_eu_west_1) > 0 ? {
      "eu-west-1" = {
        rule_name = module.eventbridge_eu_west_1[0].rule_name
        rule_arn  = module.eventbridge_eu_west_1[0].rule_arn
        region    = "eu-west-1"
      }
    } : {},
    # eu-west-2
    length(module.eventbridge_eu_west_2) > 0 ? {
      "eu-west-2" = {
        rule_name = module.eventbridge_eu_west_2[0].rule_name
        rule_arn  = module.eventbridge_eu_west_2[0].rule_arn
        region    = "eu-west-2"
      }
    } : {},
    # eu-west-3
    length(module.eventbridge_eu_west_3) > 0 ? {
      "eu-west-3" = {
        rule_name = module.eventbridge_eu_west_3[0].rule_name
        rule_arn  = module.eventbridge_eu_west_3[0].rule_arn
        region    = "eu-west-3"
      }
    } : {},
    # eu-central-1
    length(module.eventbridge_eu_central_1) > 0 ? {
      "eu-central-1" = {
        rule_name = module.eventbridge_eu_central_1[0].rule_name
        rule_arn  = module.eventbridge_eu_central_1[0].rule_arn
        region    = "eu-central-1"
      }
    } : {},
    # eu-north-1
    length(module.eventbridge_eu_north_1) > 0 ? {
      "eu-north-1" = {
        rule_name = module.eventbridge_eu_north_1[0].rule_name
        rule_arn  = module.eventbridge_eu_north_1[0].rule_arn
        region    = "eu-north-1"
      }
    } : {},
    # ap-southeast-1
    length(module.eventbridge_ap_southeast_1) > 0 ? {
      "ap-southeast-1" = {
        rule_name = module.eventbridge_ap_southeast_1[0].rule_name
        rule_arn  = module.eventbridge_ap_southeast_1[0].rule_arn
        region    = "ap-southeast-1"
      }
    } : {},
    # ap-southeast-2
    length(module.eventbridge_ap_southeast_2) > 0 ? {
      "ap-southeast-2" = {
        rule_name = module.eventbridge_ap_southeast_2[0].rule_name
        rule_arn  = module.eventbridge_ap_southeast_2[0].rule_arn
        region    = "ap-southeast-2"
      }
    } : {},
    # ap-northeast-1
    length(module.eventbridge_ap_northeast_1) > 0 ? {
      "ap-northeast-1" = {
        rule_name = module.eventbridge_ap_northeast_1[0].rule_name
        rule_arn  = module.eventbridge_ap_northeast_1[0].rule_arn
        region    = "ap-northeast-1"
      }
    } : {},
    # ap-northeast-2
    length(module.eventbridge_ap_northeast_2) > 0 ? {
      "ap-northeast-2" = {
        rule_name = module.eventbridge_ap_northeast_2[0].rule_name
        rule_arn  = module.eventbridge_ap_northeast_2[0].rule_arn
        region    = "ap-northeast-2"
      }
    } : {},
    # ap-northeast-3
    length(module.eventbridge_ap_northeast_3) > 0 ? {
      "ap-northeast-3" = {
        rule_name = module.eventbridge_ap_northeast_3[0].rule_name
        rule_arn  = module.eventbridge_ap_northeast_3[0].rule_arn
        region    = "ap-northeast-3"
      }
    } : {},
    # ap-south-1
    length(module.eventbridge_ap_south_1) > 0 ? {
      "ap-south-1" = {
        rule_name = module.eventbridge_ap_south_1[0].rule_name
        rule_arn  = module.eventbridge_ap_south_1[0].rule_arn
        region    = "ap-south-1"
      }
    } : {},
    # ca-central-1
    length(module.eventbridge_ca_central_1) > 0 ? {
      "ca-central-1" = {
        rule_name = module.eventbridge_ca_central_1[0].rule_name
        rule_arn  = module.eventbridge_ca_central_1[0].rule_arn
        region    = "ca-central-1"
      }
    } : {},
    # sa-east-1
    length(module.eventbridge_sa_east_1) > 0 ? {
      "sa-east-1" = {
        rule_name = module.eventbridge_sa_east_1[0].rule_name
        rule_arn  = module.eventbridge_sa_east_1[0].rule_arn
        region    = "sa-east-1"
      }
    } : {}
  )
}

