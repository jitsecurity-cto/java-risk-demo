terraform {
  backend "s3" {
    bucket         = "solvo-terraform-state-prod"
    key            = "excessive-permissions-demo/codebuild"
    region         = "us-east-1"
    dynamodb_table = "terraform_lock_table"
  }

  required_providers {
    aws   = "~> 4.8"
    awscc = "~> 0.45.0"
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
  repo_name            = "java-risk-demo"
  service_name         = "excessive-permissions-demo-build-${terraform.workspace}"
  github_build_branch  = "main"
  build_trigger_branch = "^refs/heads/${local.workspace_settings["github_branch"]}$"
  workspace_settings   = {
    Dev = {
      log_retention         = 90
      # Need full clone in order for gitleaks to work properly
      git_clone_depth       = 0
      github_branch         = "dev"
      github_webhook_action = "PUSH"
      github_webhook_ref    = "HEAD_REF"
      do_build              = "yes"
    }
  }[terraform.workspace]
}

# Provides information about the current account
data "aws_caller_identity" "current" {}

# Our artifacts bucket
data "aws_s3_bucket" "artifacts_bucket" {
  bucket = var.artifacts_s3_bucket_name
}

# Policy document that describes who can assume the codebuild role.
# This is very unlikely to change between projects.
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

# The common codebuild policy that all codebuild roles must attach to.
data "aws_iam_policy" "codebuild_common_policy" {
  name = "codebuild-common-${terraform.workspace}"
}

# The CloudWatch log group for the project.
resource "aws_cloudwatch_log_group" "codebuild_log_group" {
  name = "/aws/codebuild/${local.service_name}"
  retention_in_days = local.workspace_settings["log_retention"]
}

# The role that codebuild assumes for the purpose of the build.
resource "aws_iam_role" "codebuild_role" {
  name               = "${local.service_name}-role"
  tags = {
    classification = "build"
  }
  description        = "Role to be used when building the ${local.repo_name} repository"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

# Attach the common codebuild policy
resource "aws_iam_role_policy_attachment" "codebuild_role_common_policy" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = data.aws_iam_policy.codebuild_common_policy.arn
}

# Basic inline policy to allow CodeBuild to run at all.
resource "aws_iam_role_policy" "codebuild_role_policy" {
  name   = "build"
  role   = aws_iam_role.codebuild_role.name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Resource = [
          aws_cloudwatch_log_group.codebuild_log_group.arn,
          "${aws_cloudwatch_log_group.codebuild_log_group.arn}:*"
        ]
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
      },
      {
        Effect   = "Allow"
        Resource = "${data.aws_s3_bucket.artifacts_bucket.arn}/${local.repo_name}/*"
        Action   = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:GetObjectTagging",
          "s3:PutObjectTagging"
        ]
      },
      {
        Effect   = "Allow"
        Resource = "arn:aws:codebuild:${var.region}:${data.aws_caller_identity.current.account_id}:report-group/${local.service_name}-*"
        Action   = [
          "codebuild:CreateReportGroup",
          "codebuild:CreateReport",
          "codebuild:UpdateReport",
          "codebuild:BatchPutTestCases"
        ]
      }
    ]
  })
}

# Get the default compute type for the build
data "aws_ssm_parameter" "build_compute_type" {
  name = "/build/default-compute-type"
}

# Get the default image for the build
data "aws_ssm_parameter" "build_image" {
  name = "/build/default-image"
}

# Defines the codebuild project
resource "aws_codebuild_project" "codebuild" {
  name          = local.service_name
  description   = "build ${local.service_name}"
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
      value = data.aws_s3_bucket.artifacts_bucket.bucket
    }

    environment_variable {
      name  = "ARTIFACTS_REPO_NAME"
      value = "maven"
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
    git_clone_depth = local.workspace_settings["git_clone_depth"]
  }

  source_version = local.workspace_settings["github_branch"]

  secondary_sources {
    location          = var.github_build_repo_url
    git_clone_depth   = 1
    source_identifier = "BUILD"
    type              = "GITHUB"
  }

  secondary_source_version {
    source_identifier = "BUILD"
    source_version    = local.github_build_branch
  }

  logs_config {
    cloudwatch_logs {
      status = "ENABLED"
    }

    s3_logs {
      status = "DISABLED"
    }
  }
}

# Defines the GitHub webhook
resource "aws_codebuild_webhook" "webhook" {
  project_name = aws_codebuild_project.codebuild.name
  build_type = "BUILD"

  filter_group {
    filter {
      type    = "EVENT"
      pattern = local.workspace_settings["github_webhook_action"]
    }

    filter {
      type    = local.workspace_settings["github_webhook_ref"]
      pattern = local.build_trigger_branch
    }

    filter {
      type                    = "COMMIT_MESSAGE"
      pattern                 = ".*SKIP_BUILD.*"
      exclude_matched_pattern = true
    }
  }
}

# Slack channel config
data "awscc_chatbot_slack_channel_configuration" "slack_channel" {
  id = "arn:aws:chatbot::${data.aws_caller_identity.current.account_id}:chat-configuration/slack-channel/codebuild-config-${terraform.workspace}"
}

# Defines Slack integration
resource "aws_codestarnotifications_notification_rule" "slack-notification" {
  detail_type    = "BASIC"
  event_type_ids = ["codebuild-project-build-state-failed", "codebuild-project-build-state-succeeded"]

  name     = "slack-notification-${local.service_name}"
  resource = aws_codebuild_project.codebuild.arn

  target {
    type    = "AWSChatbotSlack"
    address = data.awscc_chatbot_slack_channel_configuration.slack_channel.arn
  }
}
