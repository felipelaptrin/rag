resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "null_resource" "bootstrap" {
  depends_on = [aws_ecr_repository.this]

  provisioner "local-exec" {
    command = "sh ${path.module}/bootstrap-lambda/push-to-ecr.sh ${data.aws_region.current.region} ${local.account_id} ${aws_ecr_repository.this.id} ${aws_ecr_repository.this.repository_url} ${var.architecture} ${path.module}"
  }

  triggers = {
    always = timestamp()
  }
}

data "aws_iam_policy_document" "logs" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    effect    = "Allow"
    resources = ["${aws_cloudwatch_log_group.this.arn}*"]
  }
}

resource "aws_iam_role_policy" "logs" {
  name   = "${var.name}-logs"
  role   = aws_iam_role.this.name
  policy = data.aws_iam_policy_document.logs.json
}

resource "aws_iam_role_policy" "extra" {
  count = var.json_policy == null ? 0 : 1

  name   = "${var.name}-extra"
  role   = aws_iam_role.this.name
  policy = var.json_policy
}

resource "aws_iam_role" "this" {
  name = var.name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

# Attach VPC access policy when VPC mode is enabled
resource "aws_iam_role_policy_attachment" "vpc_access" {
  count = var.vpc_enabled ? 1 : 0

  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.log_group_retention_in_days
  skip_destroy      = false
}


resource "aws_lambda_function" "this" {
  depends_on = [aws_ecr_repository.this, null_resource.bootstrap]

  function_name = var.name
  description   = var.description
  publish       = false
  timeout       = var.timeout
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.this.repository_url}:bootstrap"
  architectures = [var.architecture]
  memory_size   = var.memory_size
  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.this.id
  }
  role = aws_iam_role.this.arn

  dynamic "environment" {
    for_each = length(keys(var.environment_variables)) == 0 ? [] : [true]
    content {
      variables = var.environment_variables
    }
  }

  dynamic "vpc_config" {
    for_each = var.vpc_enabled ? [true] : []
    content {
      subnet_ids         = var.subnet_ids
      security_group_ids = [aws_security_group.this[0].id]
    }
  }

  lifecycle {
    ignore_changes = [image_uri]
  }
}

########################
### VPC-related
########################
resource "aws_security_group" "this" {
  count       = var.vpc_enabled ? 1 : 0
  name        = "${var.name}-lambda-sg"
  description = "Security group for Lambda ${var.name} in VPC"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.allowed_cidr_blocks != null ? var.allowed_cidr_blocks : []
    content {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = [ingress.value]
    }
  }

  dynamic "ingress" {
    for_each = var.additional_security_group_ids
    content {
      from_port       = 0
      to_port         = 0
      protocol        = "-1"
      security_groups = [ingress.value]
    }
  }
}
