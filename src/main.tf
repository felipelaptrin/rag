########################
### VPC
########################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "v6.6.0"

  name = local.prefix
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_nat_gateway = true
  single_nat_gateway = true
}

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
  name        = "${local.prefix}/qdrant/api-key"
  description = "Qdrant API key for ${local.prefix}"
}

resource "aws_secretsmanager_secret_version" "qdrant_api_key" {
  secret_id = aws_secretsmanager_secret.qdrant_api_key.id
  secret_string = jsonencode({
    api_key = random_password.qdrant_api_key.result
  })
}

########################
### CLOUDWATCH LOGS
########################
resource "aws_cloudwatch_log_group" "qdrant" {
  name              = "/ecs/${local.prefix}-qdrant"
  retention_in_days = 30
}

########################
### QDRANT SECURITY GROUPS
########################
resource "aws_security_group" "qdrant_service" {
  name        = "${local.prefix}-qdrant-svc"
  description = "Security group for Qdrant ECS service"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Qdrant REST"
    from_port   = 6333
    to_port     = 6333
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }
  ingress {
    description = "Qdrant gRPC"
    from_port   = 6334
    to_port     = 6334
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "efs" {
  name        = "${local.prefix}-qdrant-efs"
  description = "Security group for Qdrant EFS"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "NFS from ECS tasks"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.qdrant_service.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

########################
### EFS (PERSISTENT QDRANT STORAGE)
########################
resource "aws_efs_file_system" "qdrant" {
  creation_token = "${local.prefix}-qdrant"
  encrypted      = true
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
}

resource "aws_efs_mount_target" "qdrant" {
  for_each = { for i, subnet_id in module.vpc.private_subnets : i => subnet_id }

  file_system_id  = aws_efs_file_system.qdrant.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_access_point" "qdrant" {
  file_system_id = aws_efs_file_system.qdrant.id

  posix_user {
    uid = 0
    gid = 0
  }

  root_directory {
    path = "/qdrant-data"

    creation_info {
      owner_uid   = 0
      owner_gid   = 0
      permissions = "0770"
    }
  }
}

########################
### IAM (TASK EXECUTION + TASK ROLE)
########################
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

resource "aws_iam_role_policy" "qdrant_secrets_manager" {
  name = "${local.prefix}-qdrant-secrets"
  role = aws_iam_role.qdrant_task_execution_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadQdrantApiKeySecret"
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
### ECS TASK DEFINITION (FARGATE)
########################
resource "aws_ecs_task_definition" "qdrant" {
  family                   = "${local.prefix}-qdrant"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  cpu    = tostring(var.qdrant_cpu)
  memory = tostring(var.qdrant_memory)

  execution_role_arn = aws_iam_role.qdrant_task_execution_role.arn
  task_role_arn      = aws_iam_role.qdrant_task_role.arn

  volume {
    name = "qdrant-storage"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.qdrant.id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.qdrant.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "qdrant"
      image     = var.qdrant_image
      essential = true
      portMappings = [
        {
          containerPort = 6333
          protocol      = "tcp"
        },
        {
          containerPort = 6334
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
      secrets = [
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
      readonlyRootFilesystem = false
    }
  ])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }
}

########################
### ECS SERVICE
########################
resource "aws_ecs_service" "qdrant" {
  name                   = "${local.prefix}-qdrant"
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.qdrant.arn
  desired_count          = 1
  launch_type            = "FARGATE"
  enable_execute_command = true
  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.qdrant_service.id]
    assign_public_ip = false
  }

  depends_on = [
    aws_efs_mount_target.qdrant
  ]
}

########################
### ECS CLOUD MAP
########################
resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = var.cloud_map_namespace_name
  description = "Private DNS namespace for ECS service discovery"
  vpc         = module.vpc.vpc_id
}

resource "aws_service_discovery_service" "qdrant" {
  name = "qdrant"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this.id
    dns_records {
      type = "A"
      ttl  = 10
    }
    routing_policy = "MULTIVALUE"
  }
}
