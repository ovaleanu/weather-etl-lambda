provider "aws" {
  region = local.region
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  region = var.region
  name   = var.name

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/ovaleanu"
  }
}

module "eventbridge" {
  source = "terraform-aws-modules/eventbridge/aws"

  bus_name = "weather" # "default" bus already support schedule_expression in rules

  attach_lambda_policy = true
  lambda_target_arns   = module.lambda_function_retrieve.lambda_function_arn

  schedules = {
    lambda-cron = {
      description         = "Trigger for a Lambda every weeekday at 5am"
      schedule_expression = "cron(0 5 * * MON-FRI *)"
      timezone            = "Europe/London"
      arn                 = module.lambda_function_retrieve.lambda_function_arn
      input               = jsonencode({ "job" : "cron-by-rate" })
    }
  }
}


module "iam_assumable_role_lambda_data" {

  source = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"

  trusted_role_services = [
    "lambda.amazonaws.com"
  ]
  create_role       = true
  role_name         = format("%s-%s", local.name, "lambda_data")
  role_requires_mfa = false

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/EventBridge",
  ]
}

module "s3_bucket_landing" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket_prefix = "${local.name}-weather_landing"

  # For example only - please evaluate for your env
  force_destroy = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}

module "s3_bucket_transformed" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket_prefix = "${local.name}-weather_transformed"

  # For example only - please evaluate for your env
  force_destroy = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}

module "lambda_function_etl" {
  source = "terraform-aws-modules/lambda/aws"

  function_name = "${local.name}-weather-etl"
  handler       = "index.lambda_handler"
  runtime       = "python3.8"
  create_role   = false
  lambda_role   = module.iam_assumable_role_lambda_data[0].iam_role_arn
  source_path   = "../src/weather_etl.py"
  timeout       = 10

  tags = {
    tags = local.tags
  }
}

module "lambda_function_retrieve" {
  source = "terraform-aws-modules/lambda/aws"

  function_name = "${local.name}-weather-retrieve"
  handler       = "index.lambda_handler"
  runtime       = "python3.8"
  create_role   = false
  lambda_role   = module.iam_assumable_role_lambda_data[0].iam_role_arn
  source_path   = "../src/weather_retrieve.py"
  timeout       = 10

  tags = {
    tags = local.tags
  }
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = module.s3_bucket_landing.s3_bucket_id

  lambda_function {
    lambda_function_arn = module.lambda_function_etl.lambda_function_arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "data/"
    filter_suffix       = ".csv"
  }

}
