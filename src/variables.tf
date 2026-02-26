variable "github_iam_role" {
  description = "ARN of the IAM Role used in CI/CD for this project"
  type        = string
}

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

variable "kb_data_access_roles" {
  description = "List of IAM role ARNs that should have access to the Knowledge Base OpenSearch collection"
  type        = list(string)
}

variable "kb_web_crawler_urls" {
  description = "List of seed URLs for the Bedrock Knowledge Base web crawler data source"
  type        = list(string)
  default = [
    "https://www.ebay.com/help/buying/paying-items/buying-guest?id=4035",
    "https://www.ebay.com/help/buying/returns-items-not-received-refunds-buyers/returning-item/returning-items-bought-guest?id=4065",
    "https://www.ebay.com/help/buying/returns-items-not-received-refunds-buyers/get-help-item-hasnt-arrived?id=4042",
    "https://www.ebay.com/help/buying/returns-items-not-received-refunds-buyers/returning-item/return-shipping?id=4066",
    "https://www.ebay.com/help/selling/managing-returns-refunds/manage-returns-missing-items-refunds-sellers?id=4079",
    "https://www.ebay.com/help/buying/shipping-delivery/tracking-item?id=4027",
    "https://www.ebay.com/help/buying/resolving-issues-sellers/check-status-request?id=4667",
    "https://www.ebay.com/help/buying/returns-items-not-received-refunds-buyers/ask-ebay-step-help-buyers?id=4701",
    "https://www.ebay.com/help/buying/returns-items-not-received-refunds-buyers/return-item-refund?id=4041",
    "https://www.ebay.com/help/buying/returns-items-not-received-refunds-buyers/appeal-outcome-case-buyer?id=4039",
    "https://www.ebay.com/help/selling/managing-returns-refunds/help-buyer-item-didn%E2%80%99t-receive?id=4116",
    "https://www.ebay.com/help/selling/managing-returns-refunds/handle-return-request-seller?id=4115",
    "https://www.ebay.com/help/selling/managing-returns-refunds/ask-ebay-step-help-sellers?id=4702",
    "https://www.ebay.com/help/selling/managing-returns-refunds/appeal-outcome-case-seller?id=4369",
    "https://www.ebay.com/help/selling/managing-returns-refunds/refunding-buyers?id=5182",
    "https://www.ebay.com/help/selling/getting-paid/handling-payment-disputes?id=4799",
    "https://www.ebay.com/help/selling/managing-returns-refunds/return-shipping-sellers?id=4703",
    "https://www.ebay.com/help/selling/managing-returns-refunds/handling-return-requests/setting-return-policy?id=4368",
  ]
}
