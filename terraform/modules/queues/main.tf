# =============================================================================
# Queues Module
#
# Provisions the SQS source queue and its Dead Letter Queue (DLQ).
#
# Why SQS over Kinesis: order processing is per-order independent — no
# cross-order ordering requirement. SQS cost scales to zero at zero traffic,
# and the DLQ provides native failure isolation without a separate consumer
# group. See docs/adr/ADR-001-sqs-vs-kinesis.md.
#
# maxReceiveCount is intentionally low (default 3) for fast demo visibility.
# In production use 5–10 depending on consumer retry semantics.
# =============================================================================

locals {
  name_prefix = var.name_prefix
}

# Dead Letter Queue — receives messages after maxReceiveCount failed attempts.
# Kept separate from the source queue so failed messages can be inspected and
# replayed independently without affecting the live processing stream.
resource "aws_sqs_queue" "dlq" {
  name                      = "${local.name_prefix}-dlq"
  message_retention_seconds = 1209600 # 14 days — maximum retention for investigation

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-dlq"
    Purpose = "dead-letter-queue"
  })
}

resource "aws_sqs_queue" "source" {
  name                       = "${local.name_prefix}-orders"
  visibility_timeout_seconds = var.visibility_timeout

  # Visibility timeout must be >= Lambda timeout so SQS does not redeliver
  # a message while the processor is still handling it.
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(var.tags, {
    Name    = "${local.name_prefix}-orders"
    Purpose = "source-queue"
  })
}
