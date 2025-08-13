resource "aws_s3_bucket" "athena_results" {
  bucket        = "stock-athena-results-${random_id.bucket_suffix.hex}"
  force_destroy = true
  tags = {
    Project = "stock-pipeline"
    Purpose = "athena-results"
    Env     = "dev"
  }
}

resource "aws_athena_workgroup" "wg" {
  name = "analytics"
  configuration {
    enforce_workgroup_configuration = true
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/"
    }
  }
  tags = {
    Project = "stock-pipeline"
    Purpose = "athena"
    Env     = "dev"
  }
}
