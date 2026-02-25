variable "aws_region" {
  description = "Region to deploy the resources"
  type        = string
}

variable "environment" {
  description = "Name of the environment"
  type        = string
}

variable "embedding_model_id" {
  description = "Embedding model used to perform the embedding operation"
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "llm_model_id" {
  description = "LLM used to generate response to user"
  type        = string
  default     = "google.gemma-3-4b-it"
}

variable "vpc_cidr" {
  description = "(Optional) The IPv4 CIDR block for the VPC. CIDR can be explicitly set or it can be derived from IPAM using `ipv4_netmask_length` & `ipv4_ipam_pool_id`"
  type        = string
}

variable "bastion_instance_type" {
  description = "Defines the instance type of the EC2 bastion host"
  type        = string
  default     = "t4g.nano"
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

variable "qdrant_ec2_instance_type" {
  description = "EC2 instance type to deploy Qdrant"
  type        = string
  default     = "t4g.small"
}

variable "qdrant_cpu" {
  description = "Task CPU units for Qdrant deployment. Make sure this is smaller than the memory avaible for the 'qdrant_ec2_instance_type' instance type."
  type        = number
  default     = 1024
}

variable "qdrant_memory" {
  description = "Task memory (MiB) for Qdrant deployment. Make sure this is smaller than the memory avaible for the 'qdrant_ec2_instance_type' instance type."
  type        = number
  default     = 1536
}

variable "qdrant_data_volume_size_gb" {
  type    = number
  default = 10
}

variable "cloud_map_namespace_name" {
  type        = string
  description = "Private DNS namespace name for Cloud Map"
  default     = "internal"
}
