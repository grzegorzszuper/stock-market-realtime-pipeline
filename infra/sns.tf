variable "alert_email" { type = string }

resource "aws_sns_topic" "stock_alerts" {
  name = "stock-alerts-dd861484"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.stock_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}


