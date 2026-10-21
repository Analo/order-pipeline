variable "name_prefix" {
  description = "Resource name prefix."
  type        = string
}

variable "aws_region" {
  description = "AWS region — used for constructing ARNs in policy documents."
  type        = string
}

variable "source_queue_arn" {
  description = "ARN of the SQS source queue this processor consumes from."
  type        = string
}

variable "source_queue_url" {
  description = "URL of the SQS source queue (available to Lambda if needed for requeue logic)."
  type        = string
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds."
  type        = number
}

variable "lambda_memory" {
  description = "Lambda function memory in MB."
  type        = number
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode. PAY_PER_REQUEST scales to zero at zero traffic."
  type        = string
}

variable "dynamodb_ttl_days" {
  description = "Days before processed order records expire via TTL."
  type        = number
}

variable "tags" {
  description = "Additional tags to merge onto all resources."
  type        = map(string)
  default     = {}
}
