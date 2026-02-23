########################
### S3 Bucket
########################
resource "aws_s3_bucket" "knowledge_base" {
  bucket = "${local.prefix}-${local.account_id}"
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
  name                      = "${local.prefix}-s3-events"
  message_retention_seconds = 300
  receive_wait_time_seconds = 0
  sqs_managed_sse_enabled   = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.s3_events_dlq.arn
    maxReceiveCount     = 2
  })
}

########################
### EventBridge Rule (S3-SQS Integration)
########################
resource "aws_s3_bucket_notification" "knowledge_base" {
  bucket      = aws_s3_bucket.knowledge_base.id
  eventbridge = true
}

resource "aws_sqs_queue" "s3_events_dlq" {
  name                      = "${local.prefix}-s3-events-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_cloudwatch_event_rule" "s3_object_created" {
  name        = "${local.prefix}-s3-object-created"
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
  name = "${local.prefix}-eventbridge-to-sqs"
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
  name = "${local.prefix}-eventbridge-to-sqs-policy"
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
### EventBridge Pipe (SQS-Step Functions Integration)
########################

########################
### LAMBDA - Pdf-to-text
########################
module "pdf_to_text" {
  source      = "../modules/lambda"
  name        = "${local.prefix}-pdf-to-text"
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
  environment_variables = {
    KNOWLEDGE_BASE_BUCKET = aws_s3_bucket.knowledge_base.bucket
  }
}

########################
### LAMBDA - Chunking
########################
module "chunking" {
  source      = "../modules/lambda"
  name        = "${local.prefix}-chunking"
  description = "Download a JSON (Corpus) from S3 and store the chunkings in S3 bucket"
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
  environment_variables = {
    KNOWLEDGE_BASE_BUCKET = aws_s3_bucket.knowledge_base.bucket
  }
}

########################
### LAMBDA - Embedding
########################
module "embedding" {
  source      = "../modules/lambda"
  name        = "${local.prefix}-embedding"
  description = "Read a JSONL with chunks from S3 and generate the embedding for each chunk in a vector database (Qdrant)"
  json_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:Listbucket",
          "s3:GetObject"
        ]
        Resource = [
          aws_s3_bucket.knowledge_base.arn,
          "${aws_s3_bucket.knowledge_base.arn}/*"
        ]
      },
    ]
  })
  environment_variables = {
    QDRANT_URL        = ""
    QDRANT_API_KEY    = ""
    QDRANT_COLLECTION = ""
  }
}

########################
### STEP FUNCTIONS
########################
resource "aws_iam_role" "sfn" {
  name = "${local.prefix}-sfn"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "states.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "sfn" {
  name = "${local.prefix}-sfn"
  path = "/"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "LambdaActions",
        Action = [
          "lambda:InvokeFunction",
        ]
        Effect = "Allow"
        Resource = [
          "${module.pdf_to_text.lambda_arn}:$LATEST",
          "${module.chunking.lambda_arn}:$LATEST",
          "${module.embedding.lambda_arn}:$LATEST",
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sfn" {
  role       = aws_iam_role.sfn.name
  policy_arn = aws_iam_policy.sfn.arn
}

resource "aws_sfn_state_machine" "this" {
  name     = local.prefix
  role_arn = aws_iam_role.sfn.arn
  definition = templatefile(
    "machine-definition/knowledge-base.json",
    {
      PDF_TO_TEXT_LAMBDA_ARN = module.pdf_to_text.lambda_arn
      CHUNKING_LAMBDA_ARN    = module.chunking.lambda_arn
      EMBEDDING_LAMBDA_ARN   = module.embedding.lambda_arn
    }
  )
}

########################
### STEP FUNCTIONS
########################
resource "aws_iam_role" "pipe" {
  name = "${local.prefix}-pipe"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "pipes.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "pipe" {
  name = "${local.prefix}-eventbridge-pipe"
  path = "/"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "SqsAccess",
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Effect   = "Allow"
        Resource = aws_sqs_queue.s3_events.arn
      },
      {
        Sid = "StepFunctionsAccess",
        Action = [
          "states:StartExecution",
          "states:StartSyncExecution"
        ]
        Effect   = "Allow"
        Resource = aws_sfn_state_machine.this.arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "pipe" {
  role       = aws_iam_role.pipe.name
  policy_arn = aws_iam_policy.pipe.arn
}

resource "aws_pipes_pipe" "this" {
  name     = local.prefix
  role_arn = aws_iam_role.pipe.arn
  source   = aws_sqs_queue.s3_events.arn
  target   = aws_sfn_state_machine.this.arn

  source_parameters {
    sqs_queue_parameters {
      batch_size                         = 5
      maximum_batching_window_in_seconds = 5
    }
  }

  target_parameters {
    step_function_state_machine_parameters {
      invocation_type = "FIRE_AND_FORGET"
    }
  }
}
