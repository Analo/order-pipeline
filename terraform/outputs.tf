output "api_endpoint" {
  description = "API Gateway endpoint — POST /orders to submit an order."
  value       = module.api.api_endpoint
}

output "orders_table_name" {
  description = "DynamoDB orders table name."
  value       = module.processor.orders_table_name
}

output "source_queue_url" {
  description = "SQS source queue URL — used by seed_orders.py."
  value       = module.queues.source_queue_url
}

output "dlq_url" {
  description = "Dead Letter Queue URL — inspect failed messages here."
  value       = module.queues.dlq_url
}

output "dlq_arn" {
  description = "Dead Letter Queue ARN — used by CloudWatch alarm."
  value       = module.queues.dlq_arn
}
