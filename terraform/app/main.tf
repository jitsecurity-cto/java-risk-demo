terraform {
  backend "s3" {
    bucket         = "solvo-terraform-state-prod"
    key            = "excessive-permissions-demo/app"
    region         = "us-east-1"
    dynamodb_table = "terraform_lock_table"
  }

  required_providers {
    aws   = "~> 4.8"
    tls   = "4.0.0"
    local = "2.2.3"
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      "solvo:owner" = local.service_name
    }
  }
}

locals {
  service_name     = "excessive-permissions-demo-${terraform.workspace}"
  vpc_cidr         = "10.0.0.0/16"
  app_name         = "app-orders"
  cert_common_name = "${local.app_name}.solvo.dev"
  bucket_name      = "${local.app_name}-data-${data.aws_caller_identity.current.account_id}"
  subnet_cidrs     = [
    "10.0.0.0/24",
    "10.0.1.0/24"
  ]
}

data "aws_caller_identity" "current" {}

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = {
    Name = "${local.app_name}-vpc"
  }
}

data "aws_security_group" "default_sg" {
  vpc_id = aws_vpc.vpc.id
  name   = "default"
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
  tags   = {
    Name = "${local.app_name}-ig"
  }
}

resource "aws_route" "internet_gateway_rule" {
  route_table_id         = aws_vpc.vpc.default_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
}

data "aws_availability_zones" "available_azs" {
  state = "available"
}

resource "aws_subnet" "subnet" {
  count                   = length(local.subnet_cidrs)
  cidr_block              = local.subnet_cidrs[count.index]
  vpc_id                  = aws_vpc.vpc.id
  availability_zone       = data.aws_availability_zones.available_azs.names[count.index]
  map_public_ip_on_launch = true
  tags                    = {
    Name = "${local.app_name}-subnet-${count.index}"
  }
}

resource "aws_security_group" "webapp_security_group" {
  name   = "incoming-to-webapp"
  vpc_id = aws_vpc.vpc.id
}

resource "aws_security_group" "lb_security_group" {
  name   = "incoming-to-lb"
  vpc_id = aws_vpc.vpc.id
}

resource "aws_security_group" "ssh_security_group" {
  name   = "ssh"
  vpc_id = aws_vpc.vpc.id
}

resource "aws_security_group_rule" "incoming_web_rule" {
  type                     = "ingress"
  protocol                 = "TCP"
  from_port                = 8080
  to_port                  = 8080
  source_security_group_id = aws_security_group.webapp_security_group.id
  security_group_id        = aws_security_group.webapp_security_group.id
}

resource "aws_security_group_rule" "incoming_ssh_rule" {
  type              = "ingress"
  protocol          = "TCP"
  from_port         = 22
  to_port           = 22
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ssh_security_group.id
}

resource "aws_security_group_rule" "incoming_https_rule" {
  type              = "ingress"
  protocol          = "TCP"
  from_port         = 443
  to_port           = 443
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.lb_security_group.id
}

resource "aws_lb_target_group" "target_group" {
  name     = "java-risk-demo-target-group"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id
  health_check {
    enabled  = true
    path     = "/status"
    interval = 30
    timeout  = 5
  }
}

resource "aws_lb_target_group_attachment" "target_group_ec2" {
  target_group_arn = aws_lb_target_group.target_group.arn
  target_id        = aws_instance.instance.id
}


# Generating a certificate (required if the load balancer listens on port 443)
# ----------------------------------------------------------------------------
#
# We can't use DNS validation because the Route53 zone is hosted on the dev
# account, while the certificate needs to be created in the demo account.
#
# Unfortunately we can't use email validation either, because email validation
# would have to be sent to a "solvo.cloud" email address, whereas we would
# want the certificate's domain to be under "solvo.dev".

#
#data "aws_route53_zone" "dns_zone" {
#  name = "solvo.dev"
#}
#
#resource "aws_route53_record" "validation" {
#  for_each = {
#  for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
#    name   = dvo.resource_record_name
#    record = dvo.resource_record_value
#    type   = dvo.resource_record_type
#  }
#  }
#
#  zone_id = data.aws_route53_zone.dns_zone.zone_id
#  name    = each.value.name
#  type    = each.value.type
#  records = [each.value.record]
#  ttl     = "300"
#}
#
#resource "aws_acm_certificate_validation" "default" {
#  certificate_arn         = aws_acm_certificate.cert.arn
#  validation_record_fqdns = [
#    aws_route53_record.validation.*.fqdn
#  ]
#}

#data "aws_acm_certificate" "cert" {
#  domain = local.cert_common_name
#}
#
resource "aws_lb" "load_balancer" {
  name               = "${local.app_name}-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [
    aws_security_group.webapp_security_group.id,
    aws_security_group.lb_security_group.id,
    data.aws_security_group.default_sg.id
  ]
  subnets = aws_subnet.subnet.*.id
}

resource "aws_lb_listener" "load_balancer_listener" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = 443
  protocol          = "HTTPS"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }
  certificate_arn = aws_acm_certificate.cert.arn
}

resource "aws_inspector_resource_group" "inspector_resource_group" {
  tags = {
    Name = aws_instance.instance.tags["Name"]
  }
}

resource "aws_inspector_assessment_target" "inspector_assessment_target" {
  name               = "${local.app_name} assessment target"
  resource_group_arn = aws_inspector_resource_group.inspector_resource_group.arn
}

data "aws_inspector_rules_packages" "rules" {}

resource "aws_inspector_assessment_template" "inspector_assessment_template" {
  name       = "${local.app_name} assessment template"
  target_arn = aws_inspector_assessment_target.inspector_assessment_target.arn
  duration   = 3600
  rules_package_arns = data.aws_inspector_rules_packages.rules.arns
}

# CloudWatch

data "aws_iam_policy_document" "inspector_assume_policy_document" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["events.amazonaws.com"]
      type        = "Service"
    }
    effect = "Allow"
  }
}

resource "aws_iam_role" "inspector_event_role" {
  name               = "${local.app_name}-inspector-event-role"
  assume_role_policy = data.aws_iam_policy_document.inspector_assume_policy_document.json
}

data "aws_iam_policy_document" "inspector_event_role_policy" {
  statement {
    actions = [
      "inspector:StartAssessmentRun",
    ]
    resources = [
      "*"
    ]
  }
}

resource "aws_iam_role_policy" "inspector_event" {
  name   = "java-risk-demo-inspector-event-policy"
  role   = aws_iam_role.inspector_event_role.id
  policy = data.aws_iam_policy_document.inspector_event_role_policy.json
}

resource "aws_cloudwatch_event_rule" "inspector_event_schedule" {
  name                = "${local.app_name}-schedule"
  description         = "Trigger an Inspector assessment for ${local.app_name}"
  schedule_expression = "cron(0 0/12 * * ? *)"
}

resource "aws_cloudwatch_event_target" "inspector_event_target" {
  rule     = aws_cloudwatch_event_rule.inspector_event_schedule.name
  arn      = aws_inspector_assessment_template.inspector_assessment_template.arn
  role_arn = aws_iam_role.inspector_event_role.arn
}

data "aws_iam_policy_document" "instance_profile_assume_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["ec2.amazonaws.com"]
      type        = "Service"
    }
  }
}
resource "aws_iam_role" "instance_profile_role" {
  name               = "${local.app_name}-role"
  assume_role_policy = data.aws_iam_policy_document.instance_profile_assume_policy.json
}

resource "aws_s3_bucket" "app_bucket" {
  bucket = local.bucket_name
  tags = {
    Controls = "CPRA"
  }
}

resource "aws_s3_object" "app_bucket_object" {
  bucket = aws_s3_bucket.app_bucket.bucket
  key = "file.txt"
  content = "Hello world!"
}

resource "aws_iam_role_policy_attachment" "app_role_policy_attachment" {
  role = aws_iam_role.instance_profile_role.id
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "instance_profile" {
  name = "${local.app_name}-instance-profile"
  role = aws_iam_role.instance_profile_role.name
}

resource "local_file" "cron_file" {
  filename = ".tmp/cron-file"
  content = templatefile("resources/trigger-app-orders", {
    bucket_name = aws_s3_bucket.app_bucket.bucket
    object_name = aws_s3_object.app_bucket_object.key
  })
}

resource "aws_instance" "instance" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.subnet[0].id
  vpc_security_group_ids = [
    data.aws_security_group.default_sg.id,
    aws_security_group.webapp_security_group.id,
    aws_security_group.ssh_security_group.id
  ]
  key_name = local.app_name
  tags     = {
    Name = "${local.app_name}-instance"
  }

  iam_instance_profile = aws_iam_instance_profile.instance_profile.name

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.ssh_private_key_file)
    host        = self.public_ip
  }

  provisioner "file" {
    source = "resources/init.sh"
    destination = "/tmp/init.sh"
  }

  provisioner "file" {
    source = local_file.cron_file.filename
    destination = "/tmp/cron-file"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/script.sh",
      "/tmp/init.sh ${var.api_key}",
      "chmod +x /tmp/cron-file",
      "sudo chown root:root /tmp/cron-file",
      "sudo mv /tmp/cron-file /etc/cron.weekly/"
    ]
  }

  provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no -i ${var.ssh_private_key_file} ${var.app_file} ubuntu@${self.public_ip}:~/app.war"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mv /home/ubuntu/app.war /var/lib/jetty9/webapps/app.war"
    ]
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "tls_private_key" "private_key" {
  algorithm = "RSA"
}

resource "tls_self_signed_cert" "cert" {
  private_key_pem = tls_private_key.private_key.private_key_pem
  subject {
    common_name  = local.cert_common_name
    organization = "Solvo LTD"
  }
  validity_period_hours = 24 * 365 * 10
  allowed_uses          = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
  dns_names         = [local.cert_common_name]
  is_ca_certificate = true
}

resource local_file "private" {
  content  = tls_private_key.private_key.private_key_pem
  filename = "${path.module}/.tmp/private.pem"
}

resource local_file "public" {
  content  = tls_self_signed_cert.cert.cert_pem
  filename = "${path.module}/.tmp/public.pem"
}

resource "aws_acm_certificate" "cert" {
  private_key      = tls_private_key.private_key.private_key_pem
  certificate_body = tls_self_signed_cert.cert.cert_pem
  tags             = {
    Name = "${local.app_name} certificate"
  }
}

output "load_balancer_dns_name" {
  value = aws_lb.load_balancer.dns_name
}

output "vm_public_dns" {
  value = aws_instance.instance.public_dns
}

output "lb_zone_id" {
  value = aws_lb.load_balancer.zone_id
}

output "assessment_arn" {
  value = aws_inspector_assessment_template.inspector_assessment_template.arn
}

output "public_cert" {
  value = tls_self_signed_cert.cert.cert_pem
}
