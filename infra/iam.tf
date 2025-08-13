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
