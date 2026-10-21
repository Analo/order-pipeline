# =============================================================================
# Monitoring Module
#
# CloudWatch alarms, SNS topic, and operational dashboard for the pipeline.
#
# Three alarm signals matter for this architecture:
#   1. DLQ depth > 0 — messages have exceeded maxReceiveCount; requires
#      human investigation (schema bug, poison pill, downstream outage).
#   2. Processor errors — Lambda threw an unhandled exception (not idempotency
#      hits, which are caught and logged, not re-raised).
#   3. Validator errors — validator Lambda threw (SQS unreachable, etc.).
#      A 400 from bad input is NOT an error — it's a successful rejection.
#
# All alarms route to a single SNS topic. Email subscription is optional
# (skipped if alert_email is empty) so the module works in CI without
# requiring a confirmed subscription.
# =============================================================================

# ── SNS ───────────────────────────────────────────────────────────────────────

resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"
  tags = var.tags
}

# Subscription is skipped when alert_email is empty — avoids blocking CI
# on a pending-confirmation subscription.
resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── CloudWatch Alarms ─────────────────────────────────────────────────────────

# Any message in the DLQ is an operational signal — investigate immediately.
resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name          = "${var.name_prefix}-dlq-depth"
  alarm_description   = "Messages have landed in the DLQ — exceeded maxReceiveCount."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = var.dlq_name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "processor_errors" {
  alarm_name          = "${var.name_prefix}-processor-errors"
  alarm_description   = "Processor Lambda raised an unhandled exception."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = var.processor_function_name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "validator_errors" {
  alarm_name          = "${var.name_prefix}-validator-errors"
  alarm_description   = "Validator Lambda raised an unhandled exception (not a 400 rejection)."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = var.validator_function_name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "processor_throttles" {
  alarm_name          = "${var.name_prefix}-processor-throttles"
  alarm_description   = "Processor Lambda is being throttled — concurrency limit hit."
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  dimensions          = { FunctionName = var.processor_function_name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = var.tags
}

# ── CloudWatch Dashboard ──────────────────────────────────────────────────────

resource "aws_cloudwatch_dashboard" "pipeline" {
  dashboard_name = "${var.name_prefix}-pipeline"

  dashboard_body = jsonencode({
    widgets = [
      # Row 1: Title
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "## Order Pipeline — ${var.name_prefix}\nKey signals: DLQ depth, Lambda errors, DynamoDB write throughput."
        }
      },
      # Row 2: DLQ depth
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 12
        height = 6
        properties = {
          title  = "DLQ — Messages Visible"
          view   = "timeSeries"
          region = var.aws_region
          metrics = [[
            "AWS/SQS", "ApproximateNumberOfMessagesVisible",
            "QueueName", var.dlq_name,
            { stat = "Maximum", color = "#d62728" }
          ]]
          annotations = {
            horizontal = [{ value = 1, label = "Alert threshold", color = "#d62728" }]
          }
        }
      },
      # Row 2: Processor Lambda
      {
        type   = "metric"
        x      = 12
        y      = 2
        width  = 12
        height = 6
        properties = {
          title  = "Processor — Invocations & Errors"
          view   = "timeSeries"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.processor_function_name, { stat = "Sum" }],
            ["AWS/Lambda", "Errors",      "FunctionName", var.processor_function_name, { stat = "Sum", color = "#d62728" }]
          ]
        }
      },
      # Row 3: Validator Lambda
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "Validator — Invocations & Errors"
          view   = "timeSeries"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.validator_function_name, { stat = "Sum" }],
            ["AWS/Lambda", "Errors",      "FunctionName", var.validator_function_name, { stat = "Sum", color = "#d62728" }]
          ]
        }
      },
      # Row 3: DynamoDB writes
      {
        type   = "metric"
        x      = 12
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "DynamoDB — Successful PutItem Requests"
          view   = "timeSeries"
          region = var.aws_region
          metrics = [[
            "AWS/DynamoDB", "SuccessfulRequestLatency",
            "TableName", var.orders_table_name,
            "Operation", "PutItem",
            { stat = "SampleCount" }
          ]]
        }
      }
    ]
  })
}
