data "archive_file" "ingest_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/ingest_handler.py"
  output_path = "${path.module}/../lambda/ingest_lambda.zip"
}

resource "aws_lambda_function" "ingest" {
  function_name = "stock-ingest-${random_id.bucket_suffix.hex}"
  role          = aws_iam_role.lambda_basic_role.arn
  handler       = "ingest_handler.lambda_handler"
  runtime       = "python3.12"
  filename      = data.archive_file.ingest_zip.output_path
  timeout       = 15
  memory_size   = 256

  environment {
    variables = {
      RAW_DATA_BUCKET = aws_s3_bucket.raw_data.bucket
      DYNAMODB_TABLE  = aws_dynamodb_table.clean.name
    }
  }

  tags = {
    Project = "stock-pipeline"
    Purpose = "ingest"
    Env     = "dev"
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
