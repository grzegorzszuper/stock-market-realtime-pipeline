# EventBridge (CRON) -> trends lambda
resource "aws_cloudwatch_event_rule" "trends_every_2min" {
  name                = "stock-trends-every-2min"
  schedule_expression = var.trends_schedule_expression
}

resource "aws_cloudwatch_event_target" "trends_target" {
  rule      = aws_cloudwatch_event_rule.trends_every_2min.name
  target_id = "lambda"
  arn       = aws_lambda_function.trends.arn
}

resource "aws_lambda_permission" "trends_allow_events" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.trends.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.trends_every_2min.arn
}
