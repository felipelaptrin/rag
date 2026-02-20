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
    command = "sh ${path.module}/bootstrap-lambda/push-to-ecr.sh ${data.aws_region.current.region} ${local.account_id} ${aws_ecr_repository.this.id} ${aws_ecr_repository.this.repository_url} ${var.architecture}"
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

  lifecycle {
    ignore_changes = [image_uri]
  }
}
