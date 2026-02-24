# src

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.14.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.31 |
| <a name="requirement_random"></a> [random](#requirement\_random) | 3.8.1 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.31 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.8.1 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_chunking"></a> [chunking](#module\_chunking) | ../modules/lambda | n/a |
| <a name="module_embedding"></a> [embedding](#module\_embedding) | ../modules/lambda | n/a |
| <a name="module_pdf_to_text"></a> [pdf\_to\_text](#module\_pdf\_to\_text) | ../modules/lambda | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_event_rule.s3_object_created](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.s3_to_sqs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_log_group.qdrant](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_service.qdrant](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.qdrant](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_efs_access_point.qdrant](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_access_point) | resource |
| [aws_efs_file_system.qdrant](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_file_system) | resource |
| [aws_efs_mount_target.qdrant](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_mount_target) | resource |
| [aws_iam_policy.pipe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.sfn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.eventbridge_to_sqs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.pipe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.qdrant_task_execution_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.qdrant_task_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.sfn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.eventbridge_to_sqs_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.qdrant_secrets_manager](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.ecs_task_exec_default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.pipe](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.sfn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_pipes_pipe.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/pipes_pipe) | resource |
| [aws_s3_bucket.knowledge_base](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_notification.knowledge_base](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_notification) | resource |
| [aws_s3_bucket_public_access_block.knowledge_base](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_secretsmanager_secret.qdrant_api_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.qdrant_api_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_security_group.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.qdrant_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_sfn_state_machine.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sfn_state_machine) | resource |
| [aws_sqs_queue.s3_events](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue.s3_events_dlq](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [random_password.qdrant_api_key](https://registry.terraform.io/providers/hashicorp/random/3.8.1/docs/resources/password) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | Region to deploy the resources | `string` | n/a | yes |
| <a name="input_deploy_qdrant_publicly"></a> [deploy\_qdrant\_publicly](#input\_deploy\_qdrant\_publicly) | Defined if Qdrant service in ECS will be deploy publicly. For dev/demo purpose we can use it publicly to save some costs (e.g. NAT Gateway, VPC Endpoints...) | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Name of the environment | `string` | n/a | yes |
| <a name="input_qdrant_cpu"></a> [qdrant\_cpu](#input\_qdrant\_cpu) | Task CPU units for Qdrant deployment | `number` | `1024` | no |
| <a name="input_qdrant_image"></a> [qdrant\_image](#input\_qdrant\_image) | Image to be used in the Qdrant deployment | `string` | `"qdrant/qdrant:v1.17"` | no |
| <a name="input_qdrant_memory"></a> [qdrant\_memory](#input\_qdrant\_memory) | Task memory (MiB) for Qdrant deployment | `number` | `2048` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs for ECS tasks and EFS mount targets | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC to deploy the Qdrant service (ECS) | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_eventbridge_rule_arn"></a> [eventbridge\_rule\_arn](#output\_eventbridge\_rule\_arn) | ARN of the EventBridge rule |
| <a name="output_eventbridge_rule_name"></a> [eventbridge\_rule\_name](#output\_eventbridge\_rule\_name) | Name of the EventBridge rule |
| <a name="output_eventbridge_to_sqs_role_arn"></a> [eventbridge\_to\_sqs\_role\_arn](#output\_eventbridge\_to\_sqs\_role\_arn) | ARN of the IAM role for EventBridge to SQS |
| <a name="output_s3_bucket_arn"></a> [s3\_bucket\_arn](#output\_s3\_bucket\_arn) | ARN of the S3 bucket |
| <a name="output_s3_bucket_name"></a> [s3\_bucket\_name](#output\_s3\_bucket\_name) | Name of the S3 bucket |
| <a name="output_sqs_dlq_arn"></a> [sqs\_dlq\_arn](#output\_sqs\_dlq\_arn) | ARN of the SQS dead letter queue |
| <a name="output_sqs_dlq_url"></a> [sqs\_dlq\_url](#output\_sqs\_dlq\_url) | URL of the SQS dead letter queue |
| <a name="output_sqs_queue_arn"></a> [sqs\_queue\_arn](#output\_sqs\_queue\_arn) | ARN of the SQS queue for S3 events |
| <a name="output_sqs_queue_url"></a> [sqs\_queue\_url](#output\_sqs\_queue\_url) | URL of the SQS queue for S3 events |
<!-- END_TF_DOCS -->
