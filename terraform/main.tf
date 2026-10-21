locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

module "queues" {
  source = "./modules/queues"

  name_prefix           = local.name_prefix
  visibility_timeout    = var.sqs_visibility_timeout
  max_receive_count     = var.sqs_max_receive_count
  tags                  = {}
}

module "processor" {
  source = "./modules/processor"

  name_prefix           = local.name_prefix
  aws_region            = var.aws_region
  source_queue_arn      = module.queues.source_queue_arn
  source_queue_url      = module.queues.source_queue_url
  lambda_timeout        = var.lambda_timeout
  lambda_memory         = var.lambda_memory
  dynamodb_billing_mode = var.dynamodb_billing_mode
  dynamodb_ttl_days     = var.dynamodb_ttl_days
  tags                  = {}
}

module "api" {
  source = "./modules/api"

  name_prefix        = local.name_prefix
  environment        = var.environment
  aws_region         = var.aws_region
  source_queue_arn   = module.queues.source_queue_arn
  source_queue_url   = module.queues.source_queue_url
  lambda_timeout     = var.lambda_timeout
  lambda_memory      = var.lambda_memory
  tags               = {}
}

module "monitoring" {
  source = "./modules/monitoring"

  name_prefix                = local.name_prefix
  aws_region                 = var.aws_region
  dlq_arn                    = module.queues.dlq_arn
  dlq_name                   = module.queues.dlq_name
  processor_function_name    = module.processor.function_name
  validator_function_name    = module.api.validator_function_name
  orders_table_name          = module.processor.orders_table_name
  alert_email                = var.alert_email
  tags                       = {}
}
