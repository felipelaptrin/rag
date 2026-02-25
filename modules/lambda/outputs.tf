output "lambda_arn" {
  description = "ARN of the Lambda"
  value       = aws_lambda_function.this.arn
}

output "lambda_name" {
  description = "Name of the lambda"
  value       = var.name
}

output "lambda_security_group_id" {
  description = "The Security Group ID of the Lambda"
  value       = local.create_security_group ? aws_security_group.this[0].id : ""
}
