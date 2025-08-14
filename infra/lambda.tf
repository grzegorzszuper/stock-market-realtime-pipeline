data "archive_file" "ingest_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/ingest_handler.py"
  output_path = "${path.module}/ingest_lambda.zip"   # zostaw w katalogu infra
}

resource "aws_lambda_function" "ingest" {
  function_name    = "stock-ingest-${random_id.bucket_suffix.hex}"
  role             = aws_iam_role.lambda_basic_role.arn
  handler          = "ingest_handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.ingest_zip.output_path
  source_code_hash = data.archive_file.ingest_zip.output_base64sha256  # ⬅️ wymusza update

  timeout     = 15
  memory_size = 256

  environment {
    variables = {
      RAW_DATA_BUCKET = aws_s3_bucket.raw_data.bucket
      DYNAMODB_TABLE  = aws_dynamodb_table.clean.name
      # CODE_REV = timestamp()   # (opcjonalnie na 1 deploy, żeby na pewno wymusić)
    }
  }
}

resource "aws_cloudwatch_log_group" "ingest_lg" {
  name              = "/aws/lambda/${aws_lambda_function.ingest.function_name}"
  retention_in_days = 3
}

resource "aws_lambda_event_source_mapping" "ingest_from_kinesis" {
  event_source_arn  = aws_kinesis_stream.stock_stream.arn
  function_name     = aws_lambda_function.ingest.arn
  starting_position = "LATEST"
  batch_size        = 100
  enabled           = true
}

# Lambda #2 (trends) – kod i funkcja
locals {
  trends_fn_name = "stock-trends-dd861484"
  trends_log_grp = "/aws/lambda/${local.trends_fn_name}"
}

data "archive_file" "trends_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/trends_handler.py"
  output_path = "${path.module}/../lambda/trends_handler.zip"
}

resource "aws_lambda_function" "trends" {
  function_name    = local.trends_fn_name
  role             = aws_iam_role.trends_role.arn
  runtime          = "python3.12"
  handler          = "trends_handler.lambda_handler"
  filename         = data.archive_file.trends_zip.output_path
  source_code_hash = data.archive_file.trends_zip.output_base64sha256
  timeout          = 30
  memory_size      = 128
  environment {
    variables = {
      DYNAMODB_TABLE = data.aws_dynamodb_table.cleaned_by_name.name
      SNS_TOPIC_ARN  = aws_sns_topic.stock_alerts.arn
    }
  }
}

# krótka retencja logów
resource "aws_cloudwatch_log_group" "trends" {
  name              = local.trends_log_grp
  retention_in_days = 3
}
