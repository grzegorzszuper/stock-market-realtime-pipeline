variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-3"
}

# === trends ===
variable "ddb_table_name" {
  type    = string
  default = "StockCleanedData"
}

variable "trends_schedule_expression" {
  type    = string
  default = "rate(2 minutes)"
}
