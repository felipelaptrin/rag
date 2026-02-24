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

variable "qdrant_image" {
  description = "Image to be used in the Qdrant deployment"
  type        = string
  default     = "qdrant/qdrant:v1.17"
}

variable "qdrant_cpu" {
  type        = number
  description = "Task CPU units"
  default     = 1024
}

variable "qdrant_memory" {
  type        = number
  description = "Task memory (MiB)"
  default     = 2048
}
