locals {
  identifier = "${var.identifier}-${var.region}"
  azs        = slice(data.aws_availability_zones.primary.names, 0, 2)
  tags       = merge({ Terraform = "true" }, var.tags)
  database_endpoint = element(split(":", data.terraform_remote_state.data.outputs.rds.openvpn-db.db_instance_endpoint), 0)
  database_port     = element(split(":", data.terraform_remote_state.data.outputs.rds.openvpn-db.db_instance_endpoint), 1)  
}