# =============================================================================
# Processor Module
#
# Lambda function that consumes from the SQS source queue and writes orders
# to DynamoDB using a conditional write for idempotency.
#
# Idempotency pattern: PutItem with ConditionExpression="attribute_not_exists(orderId)"
# If the same orderId arrives twice (SQS at-least-once delivery), the second
# write raises ConditionalCheckFailedException — the processor catches it,
# logs "idempotency hit", and skips the side effect without failing the message.
#
# Hand-rolled rather than Lambda Powertools @idempotent to make the mechanism
# explicit. See docs/adr/ADR-002-idempotency-approach.md.
# =============================================================================

locals {
  name_prefix  = var.name_prefix
  handler_path = "${path.root}/../lambda/processor"
}

# ── DynamoDB ──────────────────────────────────────────────────────────────────

resource "aws_dynamodb_table" "orders" {
  name         = "${local.name_prefix}-orders"
  billing_mode = var.dynamodb_billing_mode
  hash_key     = "orderId"

  attribute {
    name = "orderId"
    type = "S"
  }

  # TTL keeps the table clean after demos — records expire automatically.
  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-orders"
  })
}

# ── IAM ───────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "processor" {
  name = "${local.name_prefix}-processor-role"

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

resource "aws_iam_role_policy_attachment" "processor_basic" {
  role       = aws_iam_role.processor.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "processor_permissions" {
  name = "${local.name_prefix}-processor-permissions"
  role = aws_iam_role.processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ConsumeFromSQS"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = var.source_queue_arn
      },
      {
        Sid    = "WriteToDynamoDB"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.orders.arn
      }
    ]
  })
}

# ── Lambda packaging ──────────────────────────────────────────────────────────

data "archive_file" "processor" {
  type        = "zip"
  source_dir  = local.handler_path
  output_path = "${path.root}/../lambda/processor.zip"
}

# ── Lambda function ───────────────────────────────────────────────────────────

resource "aws_lambda_function" "processor" {
  function_name    = "${local.name_prefix}-processor"
  role             = aws_iam_role.processor.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.processor.output_path
  source_code_hash = data.archive_file.processor.output_base64sha256
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory

  environment {
    variables = {
      ORDERS_TABLE = aws_dynamodb_table.orders.name
      TTL_DAYS     = tostring(var.dynamodb_ttl_days)
      ENVIRONMENT  = var.name_prefix
    }
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-processor"
  })
}

# SQS triggers the processor Lambda. batch_size=10 is the SQS maximum per poll.
# bisect_batch_on_function_error=true means on a partial failure, Lambda splits
# the batch and retries only the failed half — preventing good messages from
# being stuck behind a poison pill.
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn                   = var.source_queue_arn
  function_name                      = aws_lambda_function.processor.arn
  batch_size                         = 10
  bisect_batch_on_function_error     = true
  maximum_batching_window_in_seconds = 5

  function_response_types = ["ReportBatchItemFailures"]
}
