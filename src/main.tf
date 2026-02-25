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
### Bastion Host
########################
resource "aws_security_group" "bastion" {
  name        = "${local.prefix}-bastion"
  description = "Security Group managed by Terraform"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_security_group_rule" "egress_bastion" {
  type              = "egress"
  description       = "Allow all outbound traffic"
  security_group_id = aws_security_group.bastion.id
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_iam_role" "bastion" {
  name = "${local.prefix}-bastion"
  assume_role_policy = jsonencode(
    {
      Statement = [
        {
          Action = "sts:AssumeRole"
          Effect = "Allow"
          Principal = {
            Service = "ec2.amazonaws.com"
          }
          Sid = "EC2AssumeRole"
        },
      ]
      Version = "2012-10-17"
    }
  )
}

resource "aws_iam_role_policy_attachment" "bastion" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.bastion.name
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${local.prefix}-bastion"
  path = "/"
  role = aws_iam_role.bastion.name
}

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.ubuntu_latest.id
  instance_type          = var.bastion_instance_type
  subnet_id              = module.vpc.private_subnets[0]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name
  user_data              = <<-EOT
    #!/bin/bash
    echo "Installing SSM Agent"
    sudo snap install amazon-ssm-agent --classic
    sudo snap list amazon-ssm-agent
    sudo snap start amazon-ssm-agent
    sudo snap services amazon-ssm-agent
  EOT
  vpc_security_group_ids = [aws_security_group.bastion.id]

  metadata_options {
    http_endpoint               = "enabled"
    http_protocol_ipv6          = "disabled"
    http_put_response_hop_limit = 1
    http_tokens                 = "required"
  }

  root_block_device {
    encrypted = true
  }

  tags = {
    Name = "${local.prefix}-bastion"
  }
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
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [aws_secretsmanager_secret.qdrant_api_key.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = ["arn:aws:bedrock:${var.aws_region}::foundation-model/${var.embedding_model_id}"]
      },
    ]
  })
  environment_variables = {
    QDRANT_URL        = "http://${local.qdrant_hostname}:6333"
    QDRANT_API_KEY    = aws_secretsmanager_secret.qdrant_api_key.arn
    QDRANT_COLLECTION = "kb"
  }
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
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
### SECURITY GROUPS
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

resource "aws_security_group" "ecs_container_instance" {
  name        = "${local.prefix}-ecs-ec2"
  description = "Security group for ECS EC2 container instance"
  vpc_id      = module.vpc.vpc_id

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

########################
### ECS EC2 CONTAINER INSTANCE IAM
########################
resource "aws_iam_role" "ecs_instance_role" {
  name = "${local.prefix}-ecs-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "EC2AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ecs" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ssm" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "${local.prefix}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}

########################
### ECS TASK IAM (EXECUTION + TASK ROLE)
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
### PERSISTENT EBS VOLUME FOR QDRANT DATA
########################
# Keep the volume in one AZ and place the EC2 instance in the same subnet/AZ.
# We pin to the first private subnet for simplicity.
resource "aws_ebs_volume" "qdrant_data" {
  availability_zone = data.aws_subnet.qdrant_host.availability_zone
  size              = var.qdrant_data_volume_size_gb
  type              = "gp3"
  encrypted         = true
}

########################
### ECS EC2 CONTAINER INSTANCE
########################
resource "aws_instance" "ecs_qdrant_host" {
  ami                    = data.aws_ssm_parameter.ecs_ami_arm64.value
  instance_type          = var.qdrant_ec2_instance_type
  subnet_id              = module.vpc.private_subnets[0]
  vpc_security_group_ids = [aws_security_group.ecs_container_instance.id]
  iam_instance_profile   = aws_iam_instance_profile.ecs_instance_profile.name

  # ECS optimized AMI reads /etc/ecs/ecs.config
  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    # Register instance into ECS cluster
    cat >/etc/ecs/ecs.config <<EOC
    ECS_CLUSTER=${aws_ecs_cluster.this.name}
    ECS_ENABLE_TASK_IAM_ROLE=true
    ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true
    ECS_ENABLE_AWSLOGS_EXECUTIONROLE_OVERRIDE=true
    EOC

    # Wait for the extra EBS device to appear and mount it for Qdrant data
    mkdir -p /ecs/qdrant-storage

    DEV=""
    for i in $(seq 1 60); do
      for cand in /dev/nvme1n1 /dev/xvdb; do
        if [ -b "$cand" ]; then
          DEV="$cand"
          break
        fi
      done
      if [ -n "$DEV" ]; then
        break
      fi
      sleep 2
    done

    if [ -z "$DEV" ]; then
      echo "Qdrant data EBS device not found" >&2
      exit 1
    fi

    if ! blkid "$DEV"; then
      mkfs -t xfs "$DEV"
    fi

    UUID=$(blkid -s UUID -o value "$DEV")
    grep -q "$UUID" /etc/fstab || echo "UUID=$UUID /ecs/qdrant-storage xfs defaults,nofail 0 2" >> /etc/fstab
    mount -a

    chmod 0770 /ecs/qdrant-storage
    chown root:root /ecs/qdrant-storage
  EOF

  metadata_options {
    http_endpoint               = "enabled"
    http_protocol_ipv6          = "disabled"
    http_put_response_hop_limit = 1
    http_tokens                 = "required"
  }

  root_block_device {
    encrypted = true
  }

  tags = {
    Name = "${local.prefix}-qdrant"
  }
}

resource "aws_volume_attachment" "qdrant_data" {
  device_name = "/dev/xvdb"
  volume_id   = aws_ebs_volume.qdrant_data.id
  instance_id = aws_instance.ecs_qdrant_host.id

  # Avoid "force_detach" unless recovery case
  force_detach = false
}

########################
### ECS TASK DEFINITION (EC2, HOST VOLUME -> EBS MOUNT)
########################
resource "aws_ecs_task_definition" "qdrant" {
  family                   = "${local.prefix}-qdrant"
  requires_compatibilities = ["EC2"]
  network_mode             = "awsvpc"

  cpu    = tostring(var.qdrant_cpu)
  memory = tostring(var.qdrant_memory)

  execution_role_arn = aws_iam_role.qdrant_task_execution_role.arn
  task_role_arn      = aws_iam_role.qdrant_task_role.arn

  # Host bind mount. This host path lives on the attached EBS volume
  # because the EC2 instance user_data mounts EBS to /ecs/qdrant-storage.
  volume {
    name = "qdrant-storage"

    host_path = "/ecs/qdrant-storage"
  }

  container_definitions = jsonencode([
    {
      name      = "qdrant"
      image     = var.qdrant_image
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
        command     = ["CMD-SHELL", "bash -ec 'exec 3<>/dev/tcp/127.0.0.1/6333'"]
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

  depends_on = [
    aws_volume_attachment.qdrant_data
  ]
}

########################
### ECS SERVICE
########################
resource "aws_ecs_service" "qdrant" {
  name                   = "${local.prefix}-qdrant"
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.qdrant.arn
  desired_count          = 1
  launch_type            = "EC2"
  enable_execute_command = true

  # awsvpc on EC2 gives the task its own ENI
  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.qdrant_service.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.qdrant.arn
  }

  # With a single host + single EBS-backed path, ensure only one task placement
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  depends_on = [
    aws_instance.ecs_qdrant_host,
    aws_volume_attachment.qdrant_data
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
  name = local.qdrant_hostname

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this.id
    dns_records {
      type = "A"
      ttl  = 10
    }
    routing_policy = "MULTIVALUE"
  }
}
