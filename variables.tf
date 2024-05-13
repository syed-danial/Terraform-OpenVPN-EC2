variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = ""
}

variable "identifier" {
  type    = string
  default = ""
}

variable "environment" {
  type    = string
  default = ""
}

variable "tags" {
  description = "Tags to be applied to the resource"
  default     = {}
  type        = map(any)
}

variable "ec2-instance" {
  description = "Configuration for ec2 instance"
  default = {}
  type = any
}

variable "autoscaling" {
  description = "Configuration for autoscaling group"
  default = {}
  type = any
}

variable "nlb" {
  description = "Configuration for network load balancer"
  default = {}
  type = any
}

variable "alb" {
  description = "Configuration for application load balancer"
  default = {}
  type = any
}