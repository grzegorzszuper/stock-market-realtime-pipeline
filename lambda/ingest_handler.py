import json, os, base64, boto3
from datetime import datetime

s3 = boto3.client("s3")
ddb = boto3.resource("dynamodb")

RAW_BUCKET = os.environ["RAW_DATA_BUCKET"]
TABLE_NAME = os.environ["DYNAMODB_TABLE"]
table = ddb.Table(TABLE_NAME)

def lambda_handler(event, context):
    for r in event["Records"]:
        data_b64 = r["kinesis"]["data"]
        payload = json.loads(base64.b64decode(data_b64).decode("utf-8"))

        # 1) RAW do S3 (prefix raw/)
        key = f"raw/{datetime.utcnow().strftime('%Y/%m/%d/%H%M%S_%f')}.json"
        s3.put_object(Bucket=RAW_BUCKET, Key=key, Body=json.dumps(payload).encode("utf-8"))

        # 2) CLEAN do DynamoDB
        item = {
            "symbol": str(payload["symbol"]),
            "timestamp": str(payload.get("timestamp") or datetime.utcnow().isoformat() + "Z"),
            "price": float(payload["price"]),
        }
        table.put_item(Item=item)

    return {"ok": True}
