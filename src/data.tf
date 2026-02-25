data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ec2_instance_type" "this" {
  instance_type = var.bastion_instance_type
}

data "aws_ami" "ubuntu_latest" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's AWS account ID (maintainer of Ubuntu)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-*-${local.bastion_instance_architecture == "x86_64" ? "amd64" : "arm64"}-server-*"]
  }

  filter {
    name   = "architecture"
    values = [local.bastion_instance_architecture]
  }
}

data "aws_ssm_parameter" "ecs_ami_arm64" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/arm64/recommended/image_id"
}

data "aws_subnet" "qdrant_host" {
  id = module.vpc.private_subnets[0]
}
