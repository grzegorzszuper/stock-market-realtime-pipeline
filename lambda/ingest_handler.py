import json
import os
import base64
import boto3
import logging
from datetime import datetime
from decimal import Decimal  # ⬅️ NOWE

log = logging.getLogger()
log.setLevel(logging.INFO)

s3 = boto3.client("s3")
ddb = boto3.resource("dynamodb")

RAW_BUCKET = os.environ["RAW_DATA_BUCKET"]
TABLE_NAME = os.environ["DYNAMODB_TABLE"]
table = ddb.Table(TABLE_NAME)

def lambda_handler(event, context):
    ok = 0
    fail = 0

    for r in event.get("Records", []):
        try:
            # base64 → tekst (akceptuj BOM)
            raw_bytes = base64.b64decode(r["kinesis"]["data"])
            text = raw_bytes.decode("utf-8-sig", errors="replace")
            log.info(f"Decoded payload preview: {text[:120]}")

            payload = json.loads(text)

            symbol = str(payload["symbol"])
            # 👇 DynamoDB chce Decimal, nie float
            price  = Decimal(str(payload["price"]))
            ts     = str(payload.get("timestamp") or (datetime.utcnow().isoformat() + "Z"))

            # RAW → S3
            key = f"raw/{datetime.utcnow().strftime('%Y/%m/%d/%H%M%S_%f')}.json"
            s3.put_object(
                Bucket=RAW_BUCKET,
                Key=key,
                Body=json.dumps(payload).encode("utf-8"),
                ContentType="application/json",
            )

            # CLEAN → DynamoDB
            table.put_item(Item={"symbol": symbol, "timestamp": ts, "price": price})

            ok += 1
        except Exception as e:
            fail += 1
            log.exception(f"Failed to process record: {e}")

    log.info(f"Processed OK={ok}, FAIL={fail}")
    return {"ok": ok, "fail": fail}
