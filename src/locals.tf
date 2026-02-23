locals {
  project    = "knowledge-base"
  prefix     = "${local.project}-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id
}
