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

variable "vpc_cidr" {
  description = "(Optional) The IPv4 CIDR block for the VPC. CIDR can be explicitly set or it can be derived from IPAM using `ipv4_netmask_length` & `ipv4_ipam_pool_id`"
  type        = string
}

variable "vpc_azs_number" {
  description = "Number of AZs to use when deploying the VPC"
  type        = number
  default     = 2
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

variable "cloud_map_namespace_name" {
  type        = string
  description = "Private DNS namespace name for Cloud Map"
  default     = "internal"
}
