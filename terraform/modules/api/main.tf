# =============================================================================
# API Module
#
# API Gateway REST API → Lambda validator → SQS source queue.
#
# The validator is the only entry point into the pipeline. Its job is to:
#   1. Parse and validate the incoming JSON order (required fields, non-empty
#      items, positive amount).
#   2. Reject malformed orders with 400 before they touch the queue — keeping
#      the DLQ signal clean (only processor failures end up there, not bad input).
#   3. Forward valid orders to SQS and return 202 Accepted.
#
# Lambda proxy integration is used so the Lambda controls the full response
# shape — no mapping templates required.
# =============================================================================

locals {
  handler_path = "${path.root}/../lambda/validator"
}

# ── IAM ───────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "validator" {
  name = "${var.name_prefix}-validator-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "validator_basic" {
  role       = aws_iam_role.validator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "validator_permissions" {
  name = "${var.name_prefix}-validator-permissions"
  role = aws_iam_role.validator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "WriteToSQS"
      Effect = "Allow"
      Action = [
        "sqs:SendMessage",
        "sqs:GetQueueAttributes"
      ]
      Resource = var.source_queue_arn
    }]
  })
}

# ── Lambda packaging ──────────────────────────────────────────────────────────

data "archive_file" "validator" {
  type        = "zip"
  source_dir  = local.handler_path
  output_path = "${path.root}/../lambda/validator.zip"
}

# ── Lambda function ───────────────────────────────────────────────────────────

resource "aws_lambda_function" "validator" {
  function_name    = "${var.name_prefix}-validator"
  role             = aws_iam_role.validator.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.validator.output_path
  source_code_hash = data.archive_file.validator.output_base64sha256
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory

  environment {
    variables = {
      SOURCE_QUEUE_URL = var.source_queue_url
      ENVIRONMENT      = var.name_prefix
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-validator"
  })
}

# ── API Gateway ───────────────────────────────────────────────────────────────

resource "aws_api_gateway_rest_api" "orders" {
  name        = "${var.name_prefix}-api"
  description = "Order ingestion API — validates and enqueues orders."

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-api"
  })
}

resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.orders.id
  parent_id   = aws_api_gateway_rest_api.orders.root_resource_id
  path_part   = "orders"
}

resource "aws_api_gateway_method" "post_order" {
  rest_api_id   = aws_api_gateway_rest_api.orders.id
  resource_id   = aws_api_gateway_resource.orders.id
  http_method   = "POST"
  authorization = "NONE"
}

# Lambda proxy integration — the Lambda owns the full response (status, headers, body).
resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.orders.id
  resource_id             = aws_api_gateway_resource.orders.id
  http_method             = aws_api_gateway_method.post_order.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.validator.invoke_arn
}

# Allow API Gateway to invoke the validator Lambda.
resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.validator.function_name
  principal     = "apigateway.amazonaws.com"
  # Restrict to this API only — /*/*  = any method on any stage.
  source_arn = "${aws_api_gateway_rest_api.orders.execution_arn}/*/*"
}

# Deployment triggers on resource/method/integration content changes.
# create_before_destroy prevents downtime during redeployments.
resource "aws_api_gateway_deployment" "orders" {
  rest_api_id = aws_api_gateway_rest_api.orders.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.orders.id,
      aws_api_gateway_method.post_order.id,
      aws_api_gateway_integration.lambda.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_api_gateway_integration.lambda]
}

resource "aws_api_gateway_stage" "this" {
  rest_api_id   = aws_api_gateway_rest_api.orders.id
  deployment_id = aws_api_gateway_deployment.orders.id
  stage_name    = var.environment

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-api-stage"
  })
}
