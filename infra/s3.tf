# S3 bucket na dane surowe (RAW)
resource "aws_s3_bucket" "raw_data" {
  bucket        = "stock-raw-data-${random_id.bucket_suffix.hex}"
  force_destroy = true # usuwa zawartość razem z bucketem przy destroy

  tags = {
    Project = "stock-pipeline"
    Purpose = "raw-data"
    Env     = "dev"
  }
}

# Losowy sufiks, żeby nazwa bucketu była unikalna
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Lifecycle configuration - przenoszenie do tańszych klas
resource "aws_s3_bucket_lifecycle_configuration" "raw_lifecycle" {
  bucket = aws_s3_bucket.raw_data.id

  rule {
    id     = "raw-to-intelligent-to-glacier"
    status = "Enabled"

    filter {
      prefix = "raw/"
    }

    transition {
      days          = 3
      storage_class = "INTELLIGENT_TIERING"
    }

    transition {
      days          = 7
      storage_class = "GLACIER"
    }
  }
}

# Opcjonalne wyłączenie wersjonowania
resource "aws_s3_bucket_versioning" "raw_versioning" {
  bucket = aws_s3_bucket.raw_data.id

  versioning_configuration {
    status = "Suspended"
  }
}
