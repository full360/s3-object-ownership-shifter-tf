variable "region" {}
variable "env" {}
variable "aws_s3_source_bucket_name" {}
variable "aws_s3_target_bucket_name" {}

variable "ownership_full_control" {
  default = ""
}

variable "f360_env_s3_file_copier" {
  default = "s3-file-copier-prod"
}

variable "lambda_role_name" {
  default = "s3-file-copier-lambda"
}

variable "lambda_function_name" {
  default = "s3-file-copier"
}

variable "lambda_handler_name" {
  default = "main"
}

variable "lambda_runtime" {
  default = "go1.x"
}

variable "file_filters" {
  default = ""
}

variable "common_tags" {
  type = "map"

  default = {
    Terraform   = true
    Author      = "full360"
    Department  = "Development"
    Environment = "Prod"
  }
}
