resource "aws_dynamodb_table" "clean" {
  name         = "StockCleanedData"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "symbol"
  range_key    = "timestamp"

  attribute {
    name = "symbol"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  tags = {
    Project = "stock-pipeline"
    Purpose = "clean-data"
    Env     = "dev"
  }
}
