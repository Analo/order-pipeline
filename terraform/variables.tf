variable "project_name" {
  description = "Project name — used as a prefix for all resource names."
  type        = string
  default     = "order-pipeline"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
}

variable "owner" {
  description = "Owner tag applied to all resources."
  type        = string
  default     = "Analo"
}

variable "alert_email" {
  description = "Email address for CloudWatch alarm notifications. Leave empty to skip SNS subscription."
  type        = string
  default     = ""
}

# SQS tuning
variable "sqs_visibility_timeout" {
  description = <<-EOT
    Seconds a message is hidden after being received.
    Must be >= Lambda timeout to prevent a second consumer receiving the same
    message while the first is still processing it.
  EOT
  type    = number
  default = 90
}

variable "sqs_max_receive_count" {
  description = <<-EOT
    Number of times a message can be received before being moved to the DLQ.
    Set low (3) for fast demo visibility. Use 5–10 in production depending on
    consumer retry semantics.
  EOT
  type    = number
  default = 3
}

# Lambda tuning
variable "lambda_timeout" {
  description = "Lambda function timeout in seconds."
  type        = number
  default     = 30
}

variable "lambda_memory" {
  description = "Lambda function memory in MB."
  type        = number
  default     = 256
}

# DynamoDB
variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode. PAY_PER_REQUEST scales to zero at zero traffic."
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "dynamodb_ttl_days" {
  description = "Days before processed order records expire. Keeps the table clean after demos."
  type        = number
  default     = 7
}
