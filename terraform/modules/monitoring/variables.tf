variable "name_prefix" {
  description = "Resource name prefix."
  type        = string
}

variable "aws_region" {
  description = "AWS region — used for constructing the CloudWatch dashboard URL."
  type        = string
}

variable "dlq_arn" {
  description = "ARN of the Dead Letter Queue — used for the DLQ depth alarm."
  type        = string
}

variable "dlq_name" {
  description = "Name of the Dead Letter Queue — CloudWatch SQS metrics are keyed by queue name."
  type        = string
}

variable "processor_function_name" {
  description = "Processor Lambda function name — used for Lambda error/throttle alarms."
  type        = string
}

variable "validator_function_name" {
  description = "Validator Lambda function name — used for Lambda error alarms."
  type        = string
}

variable "orders_table_name" {
  description = "DynamoDB orders table name — used for the CloudWatch dashboard widget."
  type        = string
}

variable "alert_email" {
  description = "Email address for alarm notifications. Leave empty to skip SNS subscription."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to merge onto all resources."
  type        = map(string)
  default     = {}
}
