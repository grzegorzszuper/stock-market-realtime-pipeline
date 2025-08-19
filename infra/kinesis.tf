# Strumień Kinesis do ingestu danych w czasie rzeczywistym
resource "aws_kinesis_stream" "stock_stream" {
  name             = "stock-stream-${random_id.bucket_suffix.hex}" # używa sufiksu z s3.tf
  shard_count      = 1                                             # minimalny koszt
  retention_period = 24                                            # 24h wystarczy do POC

  # Tryb PROVISIONED jest najtańszy przy 1 shardzie
  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  # Szyfrowanie KMS (klucz zarządzany przez AWS) — bez dodatkowych kosztów
  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  tags = {
    Project = "stock-pipeline"
    Purpose = "realtime-ingest"
    Env     = "dev"
  }
}

# Podstawowe metryki szardów do CloudWatch
resource "aws_kinesis_stream_consumer" "placeholder_consumer" {
  stream_arn = aws_kinesis_stream.stock_stream.arn
  name       = "consumer-${random_id.bucket_suffix.hex}"
}
