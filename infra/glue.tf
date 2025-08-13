########################################
# Glue Database + Crawler + Log Group  #
########################################

# Log group dla Glue crawlerów (krótka retencja, oszczędnie)
resource "aws_cloudwatch_log_group" "glue_crawlers" {
  name              = "/aws-glue/crawlers"
  retention_in_days = 3

  tags = {
    Project = "stock-pipeline"
    Purpose = "glue-logs"
    Env     = "dev"
  }
}

# Baza w Glue Data Catalog
resource "aws_glue_catalog_database" "raw_db" {
  name = "stock_raw_db"
}

# Crawler Glue do danych RAW w S3
resource "aws_glue_crawler" "raw_crawler" {
  name          = "stock-raw-crawler"
  role          = aws_iam_role.glue_role.arn           # rola z iam_glue.tf
  database_name = aws_glue_catalog_database.raw_db.name

  s3_target {
    path = "s3://${aws_s3_bucket.raw_data.bucket}/raw/"
  }

  # Bez harmonogramu – uruchamiany ręcznie (taniej)
  tags = {
    Project = "stock-pipeline"
    Purpose = "glue-crawler"
    Env     = "dev"
  }
}
