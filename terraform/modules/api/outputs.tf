output "api_endpoint" {
  description = "API Gateway invoke URL — base URL for POST /orders."
  value       = aws_api_gateway_stage.this.invoke_url
}

output "validator_function_name" {
  description = "Validator Lambda function name — used by monitoring for CloudWatch alarms."
  value       = aws_lambda_function.validator.function_name
}

output "validator_function_arn" {
  description = "Validator Lambda function ARN."
  value       = aws_lambda_function.validator.arn
}

output "rest_api_id" {
  description = "API Gateway REST API ID."
  value       = aws_api_gateway_rest_api.orders.id
}
