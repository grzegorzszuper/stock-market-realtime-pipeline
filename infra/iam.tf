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


# Polityka: Lambda może pisać do S3/raw i do DynamoDB
resource "aws_iam_policy" "lambda_ingest_rw" {
  name        = "lambda_ingest_s3_ddb_rw"
  description = "Allow Lambda to write RAW to S3 and cleaned to DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect: "Allow",
        Action: ["s3:PutObject"],
        Resource: ["${aws_s3_bucket.raw_data.arn}/raw/*"]
      },
      {
        Effect: "Allow",
        Action: ["dynamodb:PutItem"],
        Resource: [aws_dynamodb_table.clean.arn]
      }
    ]
  })
}

# Podpięcie polityki do roli Lambdy (utworzonej wcześniej)
resource "aws_iam_role_policy_attachment" "lambda_ingest_attach" {
  role       = aws_iam_role.lambda_basic_role.name
  policy_arn = aws_iam_policy.lambda_ingest_rw.arn
}

# Pozwól Lambdzie czytać z Kinesis (consumption permissions)
resource "aws_iam_policy" "lambda_kinesis_read" {
  name        = "lambda_kinesis_read"
  description = "Allow Lambda to read from the Kinesis data stream"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect: "Allow",
        Action: [
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:ListShards",
          "kinesis:ListStreams"
        ],
        Resource: aws_kinesis_stream.stock_stream.arn
      },
      # Stream jest szyfrowany KMS-em zarządzanym przez AWS, dajmy więc decrypt ograniczony do usługi Kinesis w tym regionie.
      {
        Effect: "Allow",
        Action: ["kms:Decrypt"],
        Resource: "*",
        Condition: {
          "StringEquals": {
            "kms:ViaService": "kinesis.eu-west-3.amazonaws.com"
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


# Rola serwisowa dla Glue
resource "aws_iam_role" "glue_role" {
  name = "stock-glue-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "glue.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

# Managed policy dla Glue (zawiera dostęp do logów itp.)
resource "aws_iam_role_policy_attachment" "glue_service_role_attach" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Polityka: Glue może listować i czytać z naszego RAW bucketa
resource "aws_iam_policy" "glue_s3_read" {
  name        = "stock-glue-s3-read"
  description = "Allow Glue crawler to read from RAW S3 bucket"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["s3:GetBucketLocation", "s3:ListBucket"],
        Resource = [aws_s3_bucket.raw_data.arn]
      },
      {
        Effect   = "Allow",
        Action   = ["s3:GetObject", "s3:GetObjectVersion"],
        Resource = ["${aws_s3_bucket.raw_data.arn}/raw/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_attach_s3_read" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.glue_s3_read.arn
}

resource "aws_iam_policy" "glue_logs" {
  name        = "stock-glue-logs-access"
  description = "Allow Glue crawler to write logs to /aws-glue/crawlers"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ],
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

# pomocniczo: kto jest kontem (do ARN-ów wyżej)
data "aws_caller_identity" "me" {}