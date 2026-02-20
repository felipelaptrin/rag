output "lambda_arn" {
  description = "ARN of the Lambda"
  value       = aws_lambda_function.this.arn
}
