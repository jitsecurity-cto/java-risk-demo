terraform {
  backend "s3" {
    bucket         = "solvo-terraform-state-prod"
    key            = "java-risk-demo/dev-dns"
    region         = "us-east-1"
    dynamodb_table = "terraform_lock_table"
  }

  required_providers {
    aws   = "~> 4.8"
  }
}

variable "lb_dns" {
  type = string
}

variable "lb_zone_id" {
  type = string
}

data "aws_route53_zone" "dns_zone" {
  name = "solvo.dev"
}

resource "aws_route53_record" "demo-app" {
  zone_id = data.aws_route53_zone.dns_zone.id
  name = "java-risk-demo.solvo.dev"
  type = "A"
  alias {
    evaluate_target_health = false
    name                   = var.lb_dns
    zone_id                = var.lb_zone_id
  }
}
