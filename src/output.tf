# output "bastion_instance_id" {
#   description = "Instance ID of the bastion host"
#   value       = try(aws_instance.bastion.id, "")
# }

output "api_gateway_url" {
  value = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.api.stage_name}"
}
