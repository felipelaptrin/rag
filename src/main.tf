########################
### S3 Bucket
########################
resource "aws_s3_bucket" "knowledge_base" {
  bucket = "${local.project}-${var.environment}-${local.account_id}"
}

resource "aws_s3_bucket_public_access_block" "knowledge_base" {
  bucket                  = aws_s3_bucket.knowledge_base.id
  restrict_public_buckets = true
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
}

########################
### SQS
########################
resource "aws_sqs_queue" "s3_events" {
  name                      = "${local.project}-${var.environment}-s3-events"
  message_retention_seconds = 300
  receive_wait_time_seconds = 0
  sqs_managed_sse_enabled   = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.s3_events_dlq.arn
    maxReceiveCount     = 2
  })
}

########################
### CloudWatch Rule (S3-SQS Integration)
########################
resource "aws_s3_bucket_notification" "knowledge_base" {
  bucket      = aws_s3_bucket.knowledge_base.id
  eventbridge = true
}

resource "aws_sqs_queue" "s3_events_dlq" {
  name                      = "${local.project}-${var.environment}-s3-events-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_cloudwatch_event_rule" "s3_object_created" {
  name        = "${local.project}-${var.environment}-s3-object-created"
  description = "Rule to capture S3 object created events in raw folder"
  event_pattern = jsonencode({
    "source" : ["aws.s3"],
    "detail-type" : ["Object Created"],
    "detail" : {
      "bucket" : {
        "name" : [aws_s3_bucket.knowledge_base.bucket]
      },
      "object" : {
        "key" : [{
          "prefix" : "raw/"
        }]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "s3_to_sqs" {
  rule      = aws_cloudwatch_event_rule.s3_object_created.name
  target_id = "SQS"
  arn       = aws_sqs_queue.s3_events.arn
  role_arn  = aws_iam_role.eventbridge_to_sqs.arn

  dead_letter_config {
    arn = aws_sqs_queue.s3_events_dlq.arn
  }
}

resource "aws_iam_role" "eventbridge_to_sqs" {
  name = "${local.project}-${var.environment}-eventbridge-to-sqs"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_to_sqs_policy" {
  name = "${local.project}-${var.environment}-eventbridge-to-sqs-policy"
  role = aws_iam_role.eventbridge_to_sqs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.s3_events.arn
      }
    ]
  })
}

########################
### LAMBDA - Pdf-to-text
########################
module "pdf_to_text" {
  source      = "../modules/lambda"
  name        = "${local.project}-${var.environment}-pdf-to-text"
  description = "Read a PDF from S3, extract it to text format and put it in S3"
  json_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:Listbucket",
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.knowledge_base.arn,
          "${aws_s3_bucket.knowledge_base.arn}/*"
        ]
      }
    ]
  })
}
