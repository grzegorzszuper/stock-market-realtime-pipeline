import os, json, time, random, datetime
import boto3
from collections import defaultdict

# --- Konfiguracja przez ENV (z sensownymi domyślnymi) ---
REGION         = os.getenv("AWS_REGION", "eu-west-3")
STREAM         = os.getenv("KINESIS_STREAM", "stock-stream-3d625614")  # <- podmień jeśli trzeba
SYMBOLS        = os.getenv("SYMBOLS", "AAPL,MSFT").split(",")
BASE_PRICE     = float(os.getenv("BASE_PRICE", "220"))     # cena startowa (jeśli nie podasz per-symbol)
VOLATILITY     = float(os.getenv("VOLATILITY", "0.08"))    # losowy szum na krok (std dev, ~0.08)
DRIFT_UP       = float(os.getenv("DRIFT_UP", "0.20"))      # stały wzrost na krok (np. 0.20 USD)
DRIFT_DOWN     = float(os.getenv("DRIFT_DOWN", "0.20"))    # stały spadek na krok
INTERVAL_SEC   = float(os.getenv("INTERVAL_SEC", "0.5"))   # odstęp między krokami
DURATION_SEC   = float(os.getenv("DURATION_SEC", "60"))    # czas trwania wysyłki
# Trendy per-symbol: format "AAPL:+,MSFT:-,GOOGL:0" (+ rośnie, - spada, 0 brak trendu)
TRENDS         = os.getenv("TRENDS", "AAPL:+,MSFT:-")

# Opcjonalny „zastrzyk” co N kroków (np. 0.6% wybicia)
SPIKE_EVERY    = int(os.getenv("SPIKE_EVERY", "0"))        # 0 = wyłącz
SPIKE_PCT      = float(os.getenv("SPIKE_PCT", "0.6"))      # procent last price (np. 0.6)

# Per-symbol BASE override: "AAPL:221.5,MSFT:218.2"
BASE_PER_SYM   = {
    s.split(":")[0]: float(s.split(":")[1])
    for s in os.getenv("BASE_PER_SYM", "").split(",")
    if ":" in s
}

# --- Parsowanie trendów ---
trend_dir = defaultdict(lambda: 0)
for kv in TRENDS.split(","):
    if ":" in kv:
        sym, d = kv.split(":")
        trend_dir[sym.strip()] = {"+" : +1, "-" : -1, "0": 0}.get(d.strip(), 0)

kinesis = boto3.client("kinesis", region_name=REGION)

def send(symbol: str, price: float):
    payload = {
        "symbol": symbol,
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
        "price": round(price, 2)
    }
    kinesis.put_record(
        StreamName=STREAM,
        PartitionKey=symbol,
        Data=json.dumps(payload).encode("utf-8")
    )
    print("Sent:", payload)

def main():
    print(f"Sending to stream: {STREAM} (region {REGION})")
    print(f"Symbols: {SYMBOLS} | Trends: {dict(trend_dir)}")
    last = {}
    step = 0
    end = time.time() + DURATION_SEC

    # inicjalizacja cen startowych
    for s in SYMBOLS:
        last[s] = BASE_PER_SYM.get(s, BASE_PRICE) + random.uniform(-0.5, 0.5)

    while time.time() < end:
        step += 1
        for s in SYMBOLS:
            base = last[s]
            # komponent trendu
            drift = 0.0
            if trend_dir[s] > 0:
                drift = DRIFT_UP
            elif trend_dir[s] < 0:
                drift = -DRIFT_DOWN
            # komponent losowy
            noise = random.gauss(0, VOLATILITY)
            price = base + drift + noise

            # opcjonalny spike co N kroków
            if SPIKE_EVERY > 0 and step % SPIKE_EVERY == 0:
                spike = base * (SPIKE_PCT / 100.0)
                # kierunek zgodny z trendem; gdy brak trendu – losowy
                sign = trend_dir[s] if trend_dir[s] != 0 else random.choice([-1, 1])
                price += sign * spike

            last[s] = price
            send(s, price)
        time.sleep(INTERVAL_SEC)
    print("Done.")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("Interrupted.")
