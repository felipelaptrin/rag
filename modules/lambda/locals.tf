locals {
  account_id = data.aws_caller_identity.current.account_id

  vpc_enabled           = var.vpc_id != null && length(var.subnet_ids) > 0
  create_security_group = local.vpc_enabled
}
