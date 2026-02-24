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

########################
### ECS CLUSTER
########################
resource "aws_ecs_cluster" "this" {
  name = local.prefix
}

########################
### QDRANT API KEY
########################
resource "random_password" "qdrant_api_key" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "qdrant_api_key" {
  name        = "qdrant/api-key"
  description = "Contains the Qdrant API Key"
}

resource "aws_secretsmanager_secret_version" "qdrant_api_key" {
  secret_id = aws_secretsmanager_secret.qdrant_api_key.id
  secret_string = jsonencode({
    api_key = random_password.qdrant_api_key.result
  })
}

########################
### QDRANT LOGS
########################
resource "aws_cloudwatch_log_group" "qdrant" {
  name              = "/ecs/${local.prefix}-qdrant"
  retention_in_days = 30
}

########################
### QDRANT IAM
########################
resource "aws_iam_role" "qdrant_instance_role" {
  name = "${local.prefix}-qdrant-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "qdrant_exec_secrets" {
  name = "${local.prefix}-qdrant-exec-secrets"
  role = aws_iam_role.qdrant_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.qdrant_api_key.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "qdrant_ecs_ec2" {
  role       = aws_iam_role.qdrant_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "qdrant_ssm" {
  role       = aws_iam_role.qdrant_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "qdrant_instance_profile" {
  name = "${local.prefix}-qdrant"
  role = aws_iam_role.qdrant_instance_role.name
}

resource "aws_iam_role" "qdrant_task_execution_role" {
  name = "${local.prefix}-qdrant-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_exec_default" {
  role       = aws_iam_role.qdrant_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "qdrant_task_role" {
  name = "${local.prefix}-qdrant-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

########################
### ECS TASK DEFINITION
########################
resource "aws_ecs_task_definition" "qdrant" {
  family                   = "qdrant"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.qdrant_task_execution_role.arn
  task_role_arn            = aws_iam_role.qdrant_task_role.arn

  volume {
    name      = "qdrant-storage"
    host_path = "/data/qdrant"
  }

  container_definitions = jsonencode([
    {
      name      = "qdrant"
      image     = var.qdrant_image
      cpu       = var.qdrant_cpu
      memory    = var.qdrant_memory
      essential = true

      portMappings = [
        {
          containerPort = 6333
          hostPort      = 6333
          protocol      = "tcp"
        },
        {
          containerPort = 6334
          hostPort      = 6334
          protocol      = "tcp"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "qdrant-storage"
          containerPath = "/qdrant/storage"
          readOnly      = false
        }
      ]

      environment = [
        {
          name      = "QDRANT__SERVICE__API_KEY"
          valueFrom = "${aws_secretsmanager_secret.qdrant_api_key.arn}:api_key::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.qdrant.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "qdrant"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO- http://127.0.0.1:6333/readyz >/dev/null || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }

      # Optional hardening. Qdrant may need write access to mounted storage only.
      readonlyRootFilesystem = false
    }
  ])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }
}
