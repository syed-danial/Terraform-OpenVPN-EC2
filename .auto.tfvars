region      = "us-east-1"
environment = "stage"
identifier  = "bidfta"
project     = "openvpn"
autoscaling = {
    name = "openvpn-server"
    openvpn_admin_username = "admin"
    instance_type = "t2.medium"
    associate_public_ip_address = true
    create_iam_instance_profile = true
    secret_description = "Secret for openvpn server"
    iam_role_description = "IAM role for openvpn instance"
    min_size = "1"
    max_size = "1"
    desired_capacity = "1"
    health_check_type = "ELB"
    health_check_grace_period = "120"
    default_cooldown = "300"
    ingress_with_cidr_block = [
        {   
            from_port   = 22
            to_port     = 22
            protocol    = "tcp"
            cidr_blocks = "0.0.0.0/0"
        },
        {
            from_port   = 943
            to_port     = 943
            protocol    = "tcp"
            cidr_blocks = "0.0.0.0/0"
        },
        {
            from_port   = 443
            to_port     = 443
            protocol    = "tcp"
            cidr_blocks = "0.0.0.0/0"
        },
        {
            from_port   = 945
            to_port     = 945
            protocol    = "tcp"
            cidr_blocks = "0.0.0.0/0"
        },
        {
            from_port   = 1194
            to_port     = 1194
            protocol    = "udp"
            cidr_blocks = "0.0.0.0/0"
        }
    ]

    egress_with_cidr_blocks = {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = "0.0.0.0/0"
    }
}

alb = {
  load_balancer_type = "application"
  name               = "alb"

  listeners = {
    "alb-443" = {
      port     = 443
      protocol = "HTTPS"
      target_group_key = "openvpn_alb_tcp"
    }
  }

  target_groups = {
    "openvpn_alb_tcp" = {
      protocol             = "HTTPS"
      port                 = 443
      target_type          = "instance"
      deregistration_delay = 120
      protocol_version     = "HTTP1"
      create_attachment    = false
      health_checks = {
        interval            = 30
        path                = "/"
        port                = 443
        healthy_threshold   = 2
        unhealthy_threshold = 2
        timeout             = 5
        protocol            = "HTTPS"
        matcher             = "200-302"
      }
    }
  }


  security_group_ingress_rules = {
    tcp-443 = {
        from_port = 443
        to_port = 443
        ip_protocol = "tcp"
        description = "ALB SG for routing traffic to 443 port"
        cidr_ipv4 = "0.0.0.0/0"
    }
  }  
    
  security_group_egress_rules = {
    all = {
        ip_protocol = "-1"
        cidr_ipv4 = "0.0.0.0/0"
    }
  }
}


nlb = {
  load_balancer_type = "network"
  name               = "nlb"

  listeners = {
    "443" = {
      port     = 443
      protocol = "TCP"
      target_group_key = "openvpn_nlb_tcp"
    },
    "1194" = {
      port     = 1194
      protocol = "UDP"
      target_group_key = "openvpn_nlb_udp"
    }
  }

  target_groups = {
    "openvpn_nlb_tcp" = {
      protocol             = "TCP"
      port                 = 443
      target_type          = "instance"
      deregistration_delay = 120
      protocol_version     = "HTTP1"
      create_attachment    = false
      health_checks = {
        interval            = 30
        port                = 443
        healthy_threshold   = 2
        unhealthy_threshold = 2
        timeout             = 5
        protocol            = "TCP"
      }
    },
    "openvpn_nlb_udp" = {
      protocol             = "UDP"
      port                 = 1194
      target_type          = "instance"
      deregistration_delay = 120
      create_attachment    = false
      health_checks = {
        interval            = 30
        timeout             = 5
        protocol            = "TCP"
        port                = "22"
        unhealthy_threshold = 3
        healthy_threshold   = 2
      }
    }
  }

  security_group_ingress_rules = {
    tcp-443 = {
        from_port = 443
        to_port = 443
        ip_protocol = "tcp"
        description = "NLB SG for routing traffic to 443 port"
        cidr_ipv4 = "0.0.0.0/0"
    }
    udp-1194={
        from_port = 1194
        to_port = 1194
        ip_protocol = "udp"
        description = "NLB SG for routing traffic to 1194 port"
        cidr_ipv4 = "0.0.0.0/0"
    }
  }  
    
  security_group_egress_rules = {
    all = {
        ip_protocol = "-1"
        cidr_ipv4 = "0.0.0.0/0"
    }
  }
}