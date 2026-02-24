variable "aws_region" {
  description = "Region to deploy the resources"
  type        = string
}

variable "environment" {
  description = "Name of the environment"
  type        = string
}

# variable "embedding_model_id" {
#   description = "Embedding model used to perform the embedding operation"
#   type        = string
#   default     = "amazon.titan-embed-text-v2:0"
# }

variable "vpc_id" {
  description = "ID of the VPC to deploy the Qdrant service (ECS)"
  type        = string
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for ECS tasks and EFS mount targets"
}

variable "qdrant_image" {
  description = "Image to be used in the Qdrant deployment"
  type        = string
  default     = "qdrant/qdrant:v1.17"
}

variable "qdrant_cpu" {
  description = "Task CPU units for Qdrant deployment"
  type        = number
  default     = 1024
}

variable "qdrant_memory" {
  description = "Task memory (MiB) for Qdrant deployment"
  type        = number
  default     = 2048
}

variable "deploy_qdrant_publicly" {
  description = "Defined if Qdrant service in ECS will be deploy publicly. For dev/demo purpose we can use it publicly to save some costs (e.g. NAT Gateway, VPC Endpoints...)"
  type        = bool
  default     = false
}
