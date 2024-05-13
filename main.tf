module "autoscaling" {
    source = "../../../modules/autoscaling-group"
    
    name   = "${local.identifier}-${var.autoscaling.name}"
    image_id = data.aws_ami.openvpn_server.id
    instance_type = var.autoscaling.instance_type
    desired_capacity = var.autoscaling.desired_capacity
    health_check_type = var.autoscaling.health_check_type
    health_check_grace_period = var.autoscaling.health_check_grace_period
    default_cooldown = var.autoscaling.default_cooldown
    max_size = var.autoscaling.max_size
    min_size = var.autoscaling.min_size
    vpc_zone_identifier = data.terraform_remote_state.network.outputs.primary_vpc_outputs.private_subnets
    target_group_arns = concat(
    [ for idx, tg in module.alb.target_groups : tg.arn],
    [ for idx, tg in module.nlb.target_groups : tg.arn]
    )

    iam_role_name = "${local.identifier}-${var.autoscaling.name}"
    create_iam_instance_profile = var.autoscaling.create_iam_instance_profile
    iam_role_description = var.autoscaling.iam_role_description
    iam_role_policies = {
        secrets_manager_policy = aws_iam_policy.secrets_manager_policy.arn
    }

    user_data = base64encode(data.template_file.openvpn-template.rendered)
    network_interfaces = [{
        associate_public_ip_address = var.autoscaling.associate_public_ip_address
        security_groups = [module.openvpn_security_group.security_group_id]  
    }]
    
    tags = local.tags
}

module "alb" {
    source    = "../../../modules/loadbalancer"
    load_balancer_type = var.alb.load_balancer_type 
    name      = "${local.identifier}-${var.alb.name}"  
    vpc_id    = data.terraform_remote_state.network.outputs.primary_vpc_outputs.vpc_id
    subnets   = data.terraform_remote_state.network.outputs.primary_vpc_outputs.public_subnets

    enable_deletion_protection = false
    listeners = {
    for idx, listener in var.alb.listeners : 
      idx => {
        port             = listener.port
        protocol         = listener.protocol
        certificate_arn = "arn:aws:acm:us-east-1:489994096722:certificate/26d0ae3d-67f4-4b14-9ce9-e2db857974ca"
        forward = {
            target_group_key = listener.target_group_key
        }
      }
    }

    target_groups = {
    for idx, tg in var.alb.target_groups : 
      idx => {
        protocol             = tg.protocol
        port                 = tg.port
        target_type          = tg.target_type
        deregistration_delay = tg.deregistration_delay
        protocol_version     = tg.protocol_version
        create_attachment    = tg.create_attachment
        health_check = {
          interval           = tg.health_checks.interval
          path               = tg.health_checks.path
          port               = tg.health_checks.port
          healthy_threshold  = tg.health_checks.healthy_threshold
          unhealthy_threshold= tg.health_checks.unhealthy_threshold
          timeout            = tg.health_checks.timeout
          protocol           = tg.health_checks.protocol
          matcher            = tg.health_checks.matcher
        }
      }
    }

    security_group_ingress_rules = var.alb.security_group_ingress_rules
    security_group_egress_rules = var.alb.security_group_egress_rules
}



module "nlb" {
    source    = "../../../modules/loadbalancer"
    
    load_balancer_type = var.nlb.load_balancer_type
    name      = "${local.identifier}-${var.nlb.name}"  
    vpc_id    = data.terraform_remote_state.network.outputs.primary_vpc_outputs.vpc_id
    subnets   = data.terraform_remote_state.network.outputs.primary_vpc_outputs.public_subnets
    enable_deletion_protection = false
    listeners = {
    for idx, listener in var.nlb.listeners : 
      idx => {
        port             = listener.port
        protocol         = listener.protocol
        # certificate_arn = "arn:aws:acm:us-east-1:489994096722:certificate/26d0ae3d-67f4-4b14-9ce9-e2db857974ca"
        forward = {
            target_group_key = listener.target_group_key
        }
      }
    }
    target_groups = {
    for idx, tg in var.nlb.target_groups : 
      idx => {
        protocol             = tg.protocol
        port                 = tg.port
        target_type          = tg.target_type
        deregistration_delay = tg.deregistration_delay
        protocol_version     = try(tg.protocol_version,null)
        create_attachment    = tg.create_attachment
        health_check = {
          interval           = tg.health_checks.interval
          path               = try(tg.health_checks.path,null)
          port               = tg.health_checks.port
          healthy_threshold  = tg.health_checks.healthy_threshold
          unhealthy_threshold= tg.health_checks.unhealthy_threshold
          timeout            = tg.health_checks.timeout
          protocol           = tg.health_checks.protocol
          matcher            = try(tg.health_checks.matcher,null)
        }
      }
    }
    security_group_ingress_rules = var.nlb.security_group_ingress_rules
    security_group_egress_rules = var.nlb.security_group_egress_rules
}

module "openvpn_security_group" {
    source = "../../../modules/security_group"
    name        = "${local.identifier}-${var.autoscaling.name}"
    vpc_id      = data.terraform_remote_state.network.outputs.primary_vpc_outputs.vpc_id
    ingress_with_cidr_blocks = [
        for rule in var.autoscaling.ingress_with_cidr_block : {
            from_port = rule.from_port
            to_port = rule.to_port
            protocol = rule.protocol
            cidr_blocks = rule.cidr_blocks
        }
    ]
    egress_with_cidr_blocks = [ var.autoscaling.egress_with_cidr_blocks ]
    tags = local.tags
}



resource "random_password" "openvpn-password" {
  special = false
  min_upper = 1
  min_special = 1
  min_numeric = 1
  length  = 16
  keepers = {
    static = "1"
  }
}

resource "aws_secretsmanager_secret" "openvpn-admin" {
  name                           = "${local.identifier}-${var.autoscaling.name}"
  description                    = "OpenVPN admin credentials."
  recovery_window_in_days        = 0
  force_overwrite_replica_secret = true
}

resource "aws_secretsmanager_secret_version" "openvpn-admin" {
  secret_id = aws_secretsmanager_secret.openvpn-admin.id
  secret_string = jsonencode({
    username = var.autoscaling.openvpn_admin_username
    password = random_password.openvpn-password.result
  })
}

resource "aws_iam_policy" "secrets_manager_policy" {
  name        = "${local.identifier}-${var.autoscaling.name}-secrets-managers"
  description = var.autoscaling.secret_description

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecrets"
        ]
        Resource = "*"
      }
    ]
  })
}