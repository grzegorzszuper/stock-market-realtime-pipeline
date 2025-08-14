#########################
# Referencje do istniejących zasobów
#########################

locals {
  ingest_fn_name = aws_lambda_function.ingest.function_name
  trends_fn_name = aws_lambda_function.trends.function_name
  kinesis_name   = aws_kinesis_stream.stock_stream.name
}

# SNS topic do powiadomień (zdefiniowany w sns.tf)
data "aws_sns_topic" "alerts" {
  arn = aws_sns_topic.stock_alerts.arn
}

#########################
# LAMBDA — błędy/throttles
#########################

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
  dimensions          = { FunctionName = local.ingest_fn_name }
  alarm_description   = "Errors > 0 in last 5 min for ${local.ingest_fn_name}"
  alarm_actions       = [data.aws_sns_topic.alerts.arn]
}

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
  dimensions          = { FunctionName = local.trends_fn_name }
  alarm_description   = "Errors > 0 in last 5 min for ${local.trends_fn_name}"
  alarm_actions       = [data.aws_sns_topic.alerts.arn]
}

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
  dimensions          = { FunctionName = local.ingest_fn_name }
  alarm_actions       = [data.aws_sns_topic.alerts.arn]
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
  dimensions          = { FunctionName = local.trends_fn_name }
  alarm_actions       = [data.aws_sns_topic.alerts.arn]
}

#########################
# KINESIS — cisza i lag
#########################

resource "aws_cloudwatch_metric_alarm" "kinesis_no_records" {
  alarm_name          = "kinesis-no-records-${local.kinesis_name}"
  namespace           = "AWS/Kinesis"
  metric_name         = "IncomingRecords"
  statistic           = "Sum"
  period              = 600            # 10 min
  evaluation_periods  = 1
  threshold           = 1              # mniej niż 1 rekord/10 min
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  dimensions          = { StreamName = local.kinesis_name }
  alarm_description   = "No incoming records in last 10 minutes on ${local.kinesis_name}"
  alarm_actions       = [data.aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "kinesis_iterator_age" {
  alarm_name          = "kinesis-iterator-age-${local.kinesis_name}"
  namespace           = "AWS/Kinesis"
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 60000          # 60 s
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { StreamName = local.kinesis_name }
  alarm_description   = "IteratorAge > 60s on ${local.kinesis_name} (consumer lag)"
  alarm_actions       = [data.aws_sns_topic.alerts.arn]
}
