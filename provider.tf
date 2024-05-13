terraform {
  required_version = "1.7.2"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.40.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Environment = "stage"
      Project     = var.project
    }
  }
}