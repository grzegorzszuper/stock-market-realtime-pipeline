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
