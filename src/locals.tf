locals {
  project    = "knowledge-base"
  prefix     = "${local.project}-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id

  azs             = slice(data.aws_availability_zones.available.names, 0, var.vpc_azs_number)
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 4)]

  bastion_instance_architecture = contains(data.aws_ec2_instance_type.this.supported_architectures, "arm64") ? "arm64" : "x86_64"

  qdrant_hostname = "qdrant"

  vector_index_name = "bedrock-kb-index"

  kb_web_crawler_url_chunks = chunklist(distinct(var.kb_web_crawler_urls), 10)
}
