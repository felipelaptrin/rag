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
