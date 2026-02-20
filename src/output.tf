# S3 Bucket outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.knowledge_base.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.knowledge_base.arn
}

# SQS Queue outputs
output "sqs_queue_url" {
  description = "URL of the SQS queue for S3 events"
  value       = aws_sqs_queue.s3_events.url
}

output "sqs_queue_arn" {
  description = "ARN of the SQS queue for S3 events"
  value       = aws_sqs_queue.s3_events.arn
}

output "sqs_dlq_url" {
  description = "URL of the SQS dead letter queue"
  value       = aws_sqs_queue.s3_events_dlq.url
}

output "sqs_dlq_arn" {
  description = "ARN of the SQS dead letter queue"
  value       = aws_sqs_queue.s3_events_dlq.arn
}

# EventBridge outputs
output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.s3_object_created.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.s3_object_created.arn
}

# IAM Role output
output "eventbridge_to_sqs_role_arn" {
  description = "ARN of the IAM role for EventBridge to SQS"
  value       = aws_iam_role.eventbridge_to_sqs.arn
}
