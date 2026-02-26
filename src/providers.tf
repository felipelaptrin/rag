provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project = "Knowledge Base"
    }
  }
}

provider "opensearch" {
  url               = aws_opensearchserverless_collection.kb.collection_endpoint
  healthcheck       = false
  sign_aws_requests = true
}
