data "aws_availability_zones" "primary" {}
data "aws_region" "current" {}

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "terraform-centralised-state-us-east-1"
    key    = "network/stage/us-east-1/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "data" {
  backend = "s3"

  config = {
    bucket = "terraform-centralised-state-us-east-1"
    key    = "data/stage/us-east-1/terraform.tfstate"
    region = "us-east-1"
  }
}

data "aws_ami" "openvpn_server" {
    owners = ["aws-marketplace"]
    name_regex = "OpenVPN Access Server Community"
    most_recent = true
    filter {
      name = "product-code"
      values = ["f2ew2wrz425a1jagnifd02u5t"]
    }

    filter {
      name   = "virtualization-type"
      values = ["hvm"]
    }

    filter {
      name   = "architecture"
      values = ["x86_64"]
    }
}


data "aws_secretsmanager_secret" "db-secrets" {
  arn = data.terraform_remote_state.data.outputs.rds.openvpn-db.db_instance_master_user_secret_arn
}

data "aws_secretsmanager_secret" "openvpn-admin" {
  arn = aws_secretsmanager_secret.openvpn-admin.arn
}

output "arns" {
  value = data.template_file.openvpn-template.rendered
}


data "template_file" "openvpn-template" {
  template = "${file("${path.module}/template/user_data.tpl")}"
  vars = {
    DB_SECRETS            = data.aws_secretsmanager_secret.db-secrets.arn
    DB_HOST               = local.database_endpoint
    DB_PORT               = local.database_port
    AWS_REGION            = data.aws_region.current.name
    OPENVPN_ADMIN_SECRETS = data.aws_secretsmanager_secret.openvpn-admin.arn
    HOSTNAME          = module.nlb.dns_name
  }
}