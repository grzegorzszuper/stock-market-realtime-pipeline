import boto3
import json
import os
import time
from datetime import datetime, timezone
import yfinance as yf

# Konfiguracja AWS
stream_name = os.environ.get("KINESIS_STREAM")
region = os.environ.get("AWS_REGION")

if not stream_name or not region:
    raise ValueError("Musisz ustawić zmienne środowiskowe: AWS_REGION i KINESIS_STREAM")

kinesis = boto3.client("kinesis", region_name=region)

# Lista spółek do śledzenia
symbols = ["AAPL", "MSFT", "GOOGL"]

def send_record(symbol, price):
    record = {
        "symbol": symbol,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "price": round(float(price), 2)
    }
    print(f"Sending: {record}")
    kinesis.put_record(
        StreamName=stream_name,
        PartitionKey=symbol,
        Data=json.dumps(record)
    )

while True:
    for sym in symbols:
        ticker = yf.Ticker(sym)
        df = ticker.history(period="1d", interval="1m")
        if not df.empty:
            price = df.tail(1)["Close"].values[0]
            send_record(sym, price)
    time.sleep(60)  # aktualizacja co 60s
