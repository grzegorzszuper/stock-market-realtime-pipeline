#########################
# INPUTS / DATA
#########################

# Jeśli używasz innych nazw funkcji, podmień tu:
locals {
  ingest_fn_name = "stock-ingest-dd861484"
  trends_fn_name = "stock-trends-dd861484"
  kinesis_name   = "stock-stream-dd861484"
  raw_bucket     = "stock-raw-data-dd861484"
}

# SNS topic do powiadomień (zdefiniowany w sns.tf)
data "aws_sns_topic" "alerts" {
  arn = aws_sns_topic.stock_alerts.arn
}

#########################
# LAMBDA ALARMS
#########################

# Błędy Lambda #1 (ingest)
resource "aws_cloudwatch_metric_alarm" "lambda_ingest_errors" {
  alarm_name          = "lambda-errors-${local.ingest_fn_name}"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = local.ingest_fn_name
  }

  alarm_description = "Errors > 0 in last 5 min for ${local.ingest_fn_name}"
  alarm_actions     = [data.aws_sns_topic.alerts.arn]
}

# Błędy Lambda #2 (trends)
resource "aws_cloudwatch_metric_alarm" "lambda_trends_errors" {
  alarm_name          = "lambda-errors-${local.trends_fn_name}"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = local.trends_fn_name
  }

  alarm_description = "Errors > 0 in last 5 min for ${local.trends_fn_name}"
  alarm_actions     = [data.aws_sns_topic.alerts.arn]
}

# (opcjonalnie) Throttles dla obu Lambd
resource "aws_cloudwatch_metric_alarm" "lambda_ingest_throttles" {
  alarm_name          = "lambda-throttles-${local.ingest_fn_name}"
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = { FunctionName = local.ingest_fn_name }
  alarm_actions = [data.aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "lambda_trends_throttles" {
  alarm_name          = "lambda-throttles-${local.trends_fn_name}"
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = { FunctionName = local.trends_fn_name }
  alarm_actions = [data.aws_sns_topic.alerts.arn]
}

#########################
# KINESIS ALARMS
#########################

# Brak ruchu: IncomingRecords ~ 0 przez 10 minut
resource "aws_cloudwatch_metric_alarm" "kinesis_no_records" {
  alarm_name          = "kinesis-no-records-${local.kinesis_name}"
  namespace           = "AWS/Kinesis"
  metric_name         = "IncomingRecords"
  statistic           = "Sum"
  period              = 600             # 10 min
  evaluation_periods  = 1
  threshold           = 1               # mniej niż 1 rekord w 10 min
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    StreamName = local.kinesis_name
  }

  alarm_description = "No incoming records in last 10 minutes on ${local.kinesis_name}"
  alarm_actions     = [data.aws_sns_topic.alerts.arn]
}

# Zator konsumenta: IteratorAge > 60s
resource "aws_cloudwatch_metric_alarm" "kinesis_iterator_age" {
  alarm_name          = "kinesis-iterator-age-${local.kinesis_name}"
  namespace           = "AWS/Kinesis"
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 60000           # 60s
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StreamName = local.kinesis_name
  }

  alarm_description = "IteratorAge > 60s on ${local.kinesis_name} (consumer lag)"
  alarm_actions     = [data.aws_sns_topic.alerts.arn]
}

#########################
# S3 LIFECYCLE (RAW)
#########################

# Lekki lifecycle: RAW wygasa po 30 dniach + sprzątanie MPU
resource "aws_s3_bucket_lifecycle_configuration" "raw_lifecycle" {
  bucket = local.raw_bucket

  rule {
    id     = "expire-raw-30d"
    status = "Enabled"

    filter {
      prefix = "raw/"
    }

    expiration {
      days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}


