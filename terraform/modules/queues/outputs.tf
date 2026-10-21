output "source_queue_arn" {
  value = aws_sqs_queue.source.arn
}

output "source_queue_url" {
  value = aws_sqs_queue.source.url
}

output "dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}

output "dlq_name" {
  value = aws_sqs_queue.dlq.name
}
