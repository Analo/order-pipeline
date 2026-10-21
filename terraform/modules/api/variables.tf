variable "name_prefix" {
  description = "Resource name prefix."
  type        = string
}

variable "environment" {
  description = "Deployment environment — used as the API Gateway stage name."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region — used for constructing the Lambda integration URI."
  type        = string
}

variable "source_queue_arn" {
  description = "ARN of the SQS source queue the validator writes to."
  type        = string
}

variable "source_queue_url" {
  description = "URL of the SQS source queue — injected into the validator Lambda as SOURCE_QUEUE_URL."
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

variable "tags" {
  description = "Additional tags to merge onto all resources."
  type        = map(string)
  default     = {}
}
