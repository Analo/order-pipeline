output "function_name" {
  description = "Processor Lambda function name — used by monitoring for CloudWatch alarms."
  value       = aws_lambda_function.processor.function_name
}

output "function_arn" {
  description = "Processor Lambda function ARN."
  value       = aws_lambda_function.processor.arn
}

output "orders_table_name" {
  description = "DynamoDB orders table name — used by monitoring dashboard and scripts."
  value       = aws_dynamodb_table.orders.name
}

output "orders_table_arn" {
  description = "DynamoDB orders table ARN."
  value       = aws_dynamodb_table.orders.arn
}
