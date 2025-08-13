resource "aws_glue_catalog_database" "raw_db" {
  name = "stock_raw_db"
}

resource "aws_glue_crawler" "raw_crawler" {
  name          = "stock-raw-crawler"
  role          = aws_iam_role.glue_role.arn
  database_name = aws_glue_catalog_database.raw_db.name

  s3_target {
    path = "s3://${aws_s3_bucket.raw_data.bucket}/raw/"
  }

  # żadnych schedule – uruchomimy ręcznie (taniej)
  tags = {
    Project = "stock-pipeline"
    Purpose = "glue-crawler"
    Env     = "dev"
  }
}

# Log group dla Glue crawlerów, krótsza retencja
resource "aws_cloudwatch_log_group" "glue_crawlers" {
  name              = "/aws-glue/crawlers"
  retention_in_days = 3
  tags = { Project = "stock-pipeline", Purpose = "glue-logs", Env = "dev" }
}

resource "aws_glue_catalog_database" "raw_db" {
  name = "stock_raw_db"
}

resource "aws_glue_crawler" "raw_crawler" {
  name          = "stock-raw-crawler"
  role          = aws_iam_role.glue_role.arn
  database_name = aws_glue_catalog_database.raw_db.name

  s3_target {
    path = "s3://${aws_s3_bucket.raw_data.bucket}/raw/"
  }
}
