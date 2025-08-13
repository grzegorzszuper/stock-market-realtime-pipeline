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
