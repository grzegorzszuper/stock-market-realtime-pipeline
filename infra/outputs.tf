output "raw_bucket_name" {
  value       = aws_s3_bucket.raw_data.bucket
  description = "Nazwa bucketa S3 na dane RAW"
}

output "kinesis_stream_name" {
  value       = aws_kinesis_stream.stock_stream.name
  description = "Nazwa strumienia Kinesis"
}

output "kinesis_stream_arn" {
  value       = aws_kinesis_stream.stock_stream.arn
  description = "ARN strumienia Kinesis"
}

output "glue_database" { value = aws_glue_catalog_database.raw_db.name }
output "glue_crawler"  { value = aws_glue_crawler.raw_crawler.name }
output "athena_results_bucket" { value = aws_s3_bucket.athena_results.bucket }
output "athena_workgroup"      { value = aws_athena_workgroup.wg.name }

output "trends_lambda_name" { value = aws_lambda_function.trends.function_name }
output "trends_lambda_arn"  { value = aws_lambda_function.trends.arn }
output "trends_rule_name"   { value = aws_cloudwatch_event_rule.trends_every_2min.name }
