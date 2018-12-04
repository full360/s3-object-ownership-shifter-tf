#--------------------------------------------------------------
# Terraform version validation
#--------------------------------------------------------------
terraform {
  required_version = ">= 0.11.8"
}

#--------------------------------------------------------------
# Providers
#--------------------------------------------------------------
# require to use AWS as provider
provider "aws" {
  version = "~> 1.36"
  region  = "${var.region}"
}

provider "null" {
  version = "~> 1.0"
}

provider "template" {
  version = "~> 1.0"
}

#--------------------------------------------------------------
# IAM Policies
#--------------------------------------------------------------
data "aws_iam_policy_document" "s3_update_object_policy_doc" {
  statement {
    actions = ["s3:GetObjectAcl",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = [
      "arn:aws:s3:::${var.aws_s3_source_bucket_name}",
      "arn:aws:s3:::${var.aws_s3_source_bucket_name}/*",
    ]
  }

  statement {
    actions = ["s3:PutObject",
      "s3:PutObjectAcl",
    ]

    resources = [
      "arn:aws:s3:::${var.aws_s3_target_bucket_name}",
      "arn:aws:s3:::${var.aws_s3_target_bucket_name}/*",
    ]
  }
}

data "aws_iam_policy_document" "cloudwatch_logs_access_policy_doc" {
  statement {
    actions = ["cloudwatch:*",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "cloudwatch_logs_access_access" {
  name   = "${var.f360_env_s3_file_copier}-cloudwatch-full-access"
  policy = "${data.aws_iam_policy_document.cloudwatch_logs_access_policy_doc.json}"
}

resource "aws_iam_policy" "s3_logs_access_access" {
  name   = "${var.f360_env_s3_file_copier}-s3-full-access"
  policy = "${data.aws_iam_policy_document.s3_update_object_policy_doc.json}"
}

data "aws_iam_policy_document" "lambda_service" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

#--------------------------------------------------------------
# Lambda Role
#--------------------------------------------------------------
resource "aws_iam_role" "lambda_role" {
  name               = "${var.f360_env_s3_file_copier}-${var.lambda_role_name}"
  assume_role_policy = "${data.aws_iam_policy_document.lambda_service.json}"
}

resource "aws_iam_policy_attachment" "cloudwatch_access" {
  name       = "${var.f360_env_s3_file_copier}-cloudwatch-full-access"
  roles      = ["${aws_iam_role.lambda_role.name}"]
  policy_arn = "${aws_iam_policy.cloudwatch_logs_access_access.arn}"
}

resource "aws_iam_policy_attachment" "s3_access" {
  name       = "${var.f360_env_s3_file_copier}-s3-full-access"
  roles      = ["${aws_iam_role.lambda_role.name}"]
  policy_arn = "${aws_iam_policy.s3_logs_access_access.arn}"
}

#--------------------------------------------------------------
# Lambda Function
#--------------------------------------------------------------
data "null_data_source" "lambda_input_file" {
  inputs {
    filename = "${replace(substr("${path.module}/build/s3copier/main.zip", length(path.cwd) + 1, -1), "/terraform/modules/s3-file-copier/" , "/")}"
  }
}

resource "aws_lambda_function" "lambda" {
  filename         = "${data.null_data_source.lambda_input_file.outputs.filename}"
  function_name    = "${var.lambda_function_name}"
  handler          = "${var.lambda_handler_name}"
  source_code_hash = "${base64sha256(file(data.null_data_source.lambda_input_file.outputs.filename))}"
  runtime          = "${var.lambda_runtime}"
  role             = "${aws_iam_role.lambda_role.arn}"
  timeout          = "20"

  environment {
    variables = {
      TARGET_S3_BUCKET       = "${var.aws_s3_target_bucket_name}"
      OWNERSHIP_FULL_CONTROL = "${var.ownership_full_control}"
      FILE_FILTER            = "${var.file_filters}"
    }
  }

  tags = "${merge(
    var.common_tags,
    map(
      "Name", "${var.lambda_function_name}"
    )
  )}"
}

resource "aws_lambda_permission" "allow_source_bucket" {
  statement_id  = "allow-execution-${var.lambda_function_name}-from-s3-bucket"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.lambda.arn}"
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${var.aws_s3_source_bucket_name}"
}

resource "aws_s3_bucket_notification" "new_file_s3_notification" {
  bucket = "${var.aws_s3_source_bucket_name}"

  lambda_function {
    lambda_function_arn = "${aws_lambda_function.lambda.arn}"
    events              = ["s3:ObjectCreated:*"]
  }
}
