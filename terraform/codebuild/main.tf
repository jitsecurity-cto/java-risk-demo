terraform {
  backend "s3" {
    bucket         = "solvo-terraform-state-prod"
    key            = "excessive-permissions-demo/codebuild"
    region         = "us-east-1"
    dynamodb_table = "terraform_lock_table"
  }

  required_providers {
    aws = "~> 4.8"
  }
}

provider "aws" {
  region = var.region
}

locals {
  repo_name          = "java-risk-demo"
  service_name       = "excessive-permissions-demo-build-${terraform.workspace}"
  workspace_settings = {
    Dev = {
      github_branch         = "dev"
      github_webhook_action = "PUSH"
      github_webhook_ref    = "HEAD_REF"
      do_build              = "yes"
    }
  }[
  terraform.workspace
  ]
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    effect = "Allow"

    principals {
      identifiers = ["codebuild.amazonaws.com"]
      type        = "Service"
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "codebuild_role" {
  name               = "${local.service_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy" "codebuild_common_policy" {
  name = "codebuild-common-${terraform.workspace}"
}

data "aws_iam_policy_document" "codebuild_role_policy" {
  statement {
    effect    = "Allow"
    resources = [
      "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${local.service_name}",
      "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${local.service_name}:*"
    ]
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
  }
  statement {
    effect    = "Allow"
    resources = [
      "arn:aws:s3:::${var.artifacts_s3_bucket_name}/${local.repo_name}/*"
    ]
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:GetObjectTagging",
      "s3:PutObjectTagging"
    ]
  }
  statement {
    effect  = "Allow"
    actions = [
      "codebuild:CreateReportGroup",
      "codebuild:CreateReport",
      "codebuild:UpdateReport",
      "codebuild:BatchPutTestCases"
    ]
    resources = [
      "arn:aws:codebuild:${var.region}:${data.aws_caller_identity.current.account_id}:report-group/${local.service_name}-*"
    ]
  }
}

resource "aws_iam_role_policy" "codebuild_role_policy" {
  name   = "code-deploy"
  role   = aws_iam_role.codebuild_role.name
  policy = data.aws_iam_policy_document.codebuild_role_policy.json
}

resource "aws_iam_role_policy_attachment" "codebuild_role_common_policy" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = data.aws_iam_policy.codebuild_common_policy.arn
}

data "aws_ssm_parameter" "build_compute_type" {
  name = "/build/default-compute-type"
}

data "aws_ssm_parameter" "build_image" {
  name = "/build/default-image"
}

resource "aws_codebuild_project" "codebuild" {
  name          = local.service_name
  description   = "Build the Java risk demo app"
  build_timeout = "5"
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = nonsensitive(data.aws_ssm_parameter.build_compute_type.value)
    image                       = nonsensitive(data.aws_ssm_parameter.build_image.value)
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "ARTIFACTS_BUCKET"
      value = var.artifacts_s3_bucket_name
    }

    environment_variable {
      name  = "REPO_NAME"
      value = local.repo_name
    }

    environment_variable {
      name  = "DO_BUILD"
      value = local.workspace_settings["do_build"]
    }

    environment_variable {
      name  = "MAVEN_CLI_OPTIONS"
      value = "--no-transfer-progress --batch-mode"
    }
  }

  source {
    type            = "GITHUB"
    location        = var.github_repo_url
    git_clone_depth = 0
  }

  source_version = local.workspace_settings["github_branch"]

  logs_config {
    cloudwatch_logs {
      status = "ENABLED"
    }

    s3_logs {
      status = "DISABLED"
    }
  }
}

resource "aws_codebuild_webhook" "webhook" {
  project_name = aws_codebuild_project.codebuild.name

  filter_group {
    filter {
      type    = "EVENT"
      pattern = local.workspace_settings["github_webhook_action"]
    }

    filter {
      type    = local.workspace_settings["github_webhook_ref"]
      pattern = local.workspace_settings["github_branch"]
    }
  }
}

resource "aws_codestarnotifications_notification_rule" "slack-notification" {
  detail_type    = "BASIC"
  event_type_ids = ["codebuild-project-build-state-failed", "codebuild-project-build-state-succeeded"]

  name     = "slack-notification-${local.service_name}"
  resource = aws_codebuild_project.codebuild.arn

  target {
    type    = "AWSChatbotSlack"
    address = "arn:aws:chatbot::${data.aws_caller_identity.current.account_id}:chat-configuration/slack-channel/codebuild-config-${terraform.workspace}"
  }
}
