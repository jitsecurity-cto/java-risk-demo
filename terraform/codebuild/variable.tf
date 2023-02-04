variable "artifacts_s3_bucket_name" {
  type = string
  default = "persolvo-build-artifacts-222"
}

variable "github_repo_url" {
  type = string
  default = "https://github.com/solvocloud/java-risk-demo.git"
}

variable "github_build_repo_url" {
  type = string
  default = "https://github.com/solvocloud/build.git"
}

variable "region" {
  type = string
  default = "us-east-1"
}
