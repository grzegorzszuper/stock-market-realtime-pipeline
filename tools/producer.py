import os, json, time, random, datetime
import boto3

REGION = os.getenv("AWS_REGION", "eu-west-3")
STREAM = os.getenv("KINESIS_STREAM", "stock-stream-d1c65ad7")  # podmień jeśli inna nazwa
SYMBOLS = os.getenv("SYMBOLS", "AAPL,MSFT").split(",")

kinesis = boto3.client("kinesis", region_name=REGION)

def send_once(symbol: str):
    price = round(220 + random.uniform(-2, 2), 2)
    payload = {
        "symbol": symbol,
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
        "price": price
    }
    kinesis.put_record(
        StreamName=STREAM,
        PartitionKey=symbol,
        Data=json.dumps(payload).encode("utf-8")
    )
    print("Sent:", payload)

if __name__ == "__main__":
    print(f"Sending to stream: {STREAM} in region {REGION}")
    try:
        # ~2 rekordy/sek przez ~60s (łatwo przerwać)
        end = time.time() + 60
        while time.time() < end:
            for s in SYMBOLS:
                send_once(s)
            time.sleep(0.5)
    except KeyboardInterrupt:
        pass
    print("Done.")
