########################################
# CloudWatch Alarms (Lambda + Kinesis)
# — bez locals, bez data, bez duplikatów
########################################

# ===== LAMBDA: Errors / Throttles =====

resource "aws_cloudwatch_metric_alarm" "lambda_ingest_errors" {
  alarm_name          = "lambda-errors-${aws_lambda_function.ingest.function_name}"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.ingest.function_name
  }

  alarm_description = "Errors > 0 in last 5 min for ${aws_lambda_function.ingest.function_name}"
  alarm_actions     = [aws_sns_topic.stock_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "lambda_trends_errors" {
  alarm_name          = "lambda-errors-${aws_lambda_function.trends.function_name}"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.trends.function_name
  }

  alarm_description = "Errors > 0 in last 5 min for ${aws_lambda_function.trends.function_name}"
  alarm_actions     = [aws_sns_topic.stock_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "lambda_ingest_throttles" {
  alarm_name          = "lambda-throttles-${aws_lambda_function.ingest.function_name}"
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.ingest.function_name
  }

  alarm_actions = [aws_sns_topic.stock_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "lambda_trends_throttles" {
  alarm_name          = "lambda-throttles-${aws_lambda_function.trends.function_name}"
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.trends.function_name
  }

  alarm_actions = [aws_sns_topic.stock_alerts.arn]
}

# ===== KINESIS: brak ruchu / lag konsumenta =====

resource "aws_cloudwatch_metric_alarm" "kinesis_no_records" {
  alarm_name          = "kinesis-no-records-${aws_kinesis_stream.stock_stream.name}"
  namespace           = "AWS/Kinesis"
  metric_name         = "IncomingRecords"
  statistic           = "Sum"
  period              = 600 # 10 min
  evaluation_periods  = 1
  threshold           = 1 # <1 rekord / 10 min
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    StreamName = aws_kinesis_stream.stock_stream.name
  }

  alarm_description = "No incoming records in last 10 minutes on ${aws_kinesis_stream.stock_stream.name}"
  alarm_actions     = [aws_sns_topic.stock_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "kinesis_iterator_age" {
  alarm_name          = "kinesis-iterator-age-${aws_kinesis_stream.stock_stream.name}"
  namespace           = "AWS/Kinesis"
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 60000 # 60 s
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StreamName = aws_kinesis_stream.stock_stream.name
  }

  alarm_description = "IteratorAge > 60s on ${aws_kinesis_stream.stock_stream.name} (consumer lag)"
  alarm_actions     = [aws_sns_topic.stock_alerts.arn]
}
