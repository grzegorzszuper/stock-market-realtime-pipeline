resource "aws_iam_role" "lambda_basic_role" {
  name = "lambda_basic_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "lambda_basic_execution" {
  name       = "lambda_basic_execution_policy"
  roles      = [aws_iam_role.lambda_basic_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --- Lambda ingest: write to S3 raw + DynamoDB clean
resource "aws_iam_policy" "lambda_ingest_rw" {
  name        = "lambda_ingest_s3_ddb_rw"
  description = "Allow Lambda to write RAW to S3 and cleaned to DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${aws_s3_bucket.raw_data.arn}/raw/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = [aws_dynamodb_table.clean.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_ingest_attach" {
  role       = aws_iam_role.lambda_basic_role.name
  policy_arn = aws_iam_policy.lambda_ingest_rw.arn
}

# --- Lambda ingest: read from Kinesis
resource "aws_iam_policy" "lambda_kinesis_read" {
  name        = "lambda_kinesis_read"
  description = "Allow Lambda to read from the Kinesis data stream"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:ListShards",
          "kinesis:ListStreams"
        ]
        Resource = aws_kinesis_stream.stock_stream.arn
      },
      # optional: decrypt via Kinesis service (AWS-owned key)
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "kinesis.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_kinesis_read_attach" {
  role       = aws_iam_role.lambda_basic_role.name
  policy_arn = aws_iam_policy.lambda_kinesis_read.arn
}

# --- Glue service role
resource "aws_iam_role" "glue_role" {
  name = "stock-glue-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service_role_attach" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_policy" "glue_s3_read" {
  name        = "stock-glue-s3-read"
  description = "Allow Glue crawler to read from RAW S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation", "s3:ListBucket"]
        Resource = [aws_s3_bucket.raw_data.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = ["${aws_s3_bucket.raw_data.arn}/raw/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_attach_s3_read" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.glue_s3_read.arn
}

data "aws_caller_identity" "me" {}

resource "aws_iam_policy" "glue_logs" {
  name        = "stock-glue-logs-access"
  description = "Allow Glue crawler to write logs to /aws-glue/crawlers"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.me.account_id}:log-group:/aws-glue/crawlers",
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.me.account_id}:log-group:/aws-glue/crawlers:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_attach_logs" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.glue_logs.arn
}

# --- Lambda #2 (trends)
resource "aws_iam_role" "trends_role" {
  name = "stock-trends-role-dd861484"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "trends_policy" {
  name = "stock-trends-policy-dd861484"
  role = aws_iam_role.trends_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:Query", "dynamodb:Scan", "dynamodb:GetItem", "dynamodb:DescribeTable", "dynamodb:BatchGetItem"]
        Resource = [aws_dynamodb_table.clean.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.stock_alerts.arn
      }
    ]
  })
}
