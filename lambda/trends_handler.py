import os
import json
import boto3
import decimal
import logging
from datetime import datetime, timezone
from boto3.dynamodb.conditions import Key

# === Konfiguracja z env (z sensownymi domyślnymi) ===
DDB_TABLE       = os.environ["DYNAMODB_TABLE"]
SNS_TOPIC_ARN   = os.environ["SNS_TOPIC_ARN"]

THRESH_PCT      = float(os.getenv("THRESH_PCT", 1.5))   # próg zmiany % vs lookback
SMA_WINDOW      = int(os.getenv("SMA_WINDOW", 20))      # okno SMA
LOOKBACK_POINTS = int(os.getenv("LOOKBACK_POINTS", 15)) # ile ostatnich punktów porównujemy
MIN_POINTS      = int(os.getenv("MIN_POINTS", 20))      # minimalna liczba punktów do decyzji
EPS_PCT         = float(os.getenv("EPS_PCT", 0.2))      # czułość odchyłki od SMA (filtr szumu)

# Uwaga: LOOKBACK_POINTS ~ "minuty" jeżeli feed jest co minutę.
# Jeśli wysyłasz rzadziej/częściej, dopasuj wartość.

# === Boto3 ===
dynamodb = boto3.resource("dynamodb")
table    = dynamodb.Table(DDB_TABLE)
sns      = boto3.client("sns")

# === Logowanie ===
log = logging.getLogger()
log.setLevel(logging.INFO)

# === Helpers ===
def _to_float(x):
    if isinstance(x, decimal.Decimal):
        return float(x)
    return float(x)

def _sma(vals, n):
    if len(vals) < n or n <= 0:
        return None
    return sum(vals[-n:]) / n

def _iso_now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

def _distinct_symbols(limit=200):
    """Zwraca listę unikalnych symboli. Scan wystarcza do demo/małej skali."""
    syms = set()
    resp = table.scan(
        ProjectionExpression="#s",
        ExpressionAttributeNames={"#s": "symbol"}
    )
    syms.update(i["symbol"] for i in resp.get("Items", []) if "symbol" in i)
    while "LastEvaluatedKey" in resp and len(syms) < limit:
        resp = table.scan(
            ProjectionExpression="#s",
            ExpressionAttributeNames={"#s": "symbol"},
            ExclusiveStartKey=resp["LastEvaluatedKey"]
        )
        syms.update(i["symbol"] for i in resp.get("Items", []) if "symbol" in i)
    return list(syms)[:limit]

def _series_for_symbol(sym, limit=200):
    """
    Pobiera do 'limit' najnowszych rekordów danego symbolu,
    zwraca listę (ts_iso, price) posortowaną rosnąco po czasie.
    """
    resp = table.query(
        KeyConditionExpression=Key("symbol").eq(sym),
        ScanIndexForward=False,  # najnowsze najpierw
        Limit=limit
    )
    items = list(reversed(resp.get("Items", [])))  # teraz rosnąco
    series = []
    for it in items:
        if "price" in it and "timestamp" in it:
            series.append((str(it["timestamp"]), _to_float(it["price"])))
    return series

def _decide_action(series):
    """
    Serce logiki:
    - Liczymy SMA z okna SMA_WINDOW
    - Liczymy zmianę procentową względem wartości sprzed LOOKBACK_POINTS
    - Filtrujemy szum: wymagamy oddalenia od SMA > EPS_PCT
    Zwraca: (action, payload_dict) lub (None, reason)
    """
    if len(series) < max(MIN_POINTS, SMA_WINDOW, LOOKBACK_POINTS + 1):
        return None, "too_few_points"

    # przygotuj wektory
    prices = [p for _, p in series]
    last   = prices[-1]

    sma = _sma(prices, SMA_WINDOW)
    if sma is None or sma == 0:
        return None, "sma_unavailable"

    # punkt referencyjny wstecz o LOOKBACK_POINTS
    ref_idx = max(0, len(prices) - 1 - LOOKBACK_POINTS)
    ref = prices[ref_idx]
    if ref == 0:
        return None, "ref_zero"

    delta_pct = (last / ref - 1.0) * 100.0
    dev_pct   = abs((last - sma) / sma) * 100.0

    # filtr szumu
    if dev_pct < EPS_PCT:
        return None, "near_sma_noise"

    # prosta reguła BUY/SELL
    if delta_pct <= -THRESH_PCT and last < sma:
        payload = {
            "action": "BUY",
            "delta_pct": delta_pct,
            "last": last,
            "sma": sma,
            "dev_pct": dev_pct
        }
        return "BUY", payload

    if delta_pct >= THRESH_PCT and last > sma:
        payload = {
            "action": "SELL",
            "delta_pct": delta_pct,
            "last": last,
            "sma": sma,
            "dev_pct": dev_pct
        }
        return "SELL", payload

    return None, "no_signal"

def _format_message(symbol, action, payload):
    now = _iso_now()
    emoji = "📉" if action == "BUY" else "📈"  # spadek ⇒ BUY, wzrost ⇒ SELL
    return (
        f"{emoji} Stock Alert — {symbol}\n"
        f"⏰ {now}\n"
        f"Action: {action}\n"
        f"Reason: {payload['delta_pct']:+.2f}% vs last {LOOKBACK_POINTS} pt(s) "
        f"and price {'below' if action=='BUY' else 'above'} SMA{SMA_WINDOW}\n"
        f"Last: {payload['last']:.2f}\n"
        f"SMA{SMA_WINDOW}: {payload['sma']:.2f} (diff: {payload['dev_pct']:.2f}%)\n"
        f"Params: THRESH_PCT={THRESH_PCT}%, LOOKBACK_POINTS={LOOKBACK_POINTS}, "
        f"SMA_WINDOW={SMA_WINDOW}, MIN_POINTS={MIN_POINTS}, EPS_PCT={EPS_PCT}%"
    )

# === Handler ===
def lambda_handler(event, context):
    log.info(
        f"Config: THRESH_PCT={THRESH_PCT} LOOKBACK_POINTS={LOOKBACK_POINTS} "
        f"SMA_WINDOW={SMA_WINDOW} MIN_POINTS={MIN_POINTS} EPS_PCT={EPS_PCT}"
    )

    alerts = []
    symbols = _distinct_symbols()
    log.info(f"Found symbols: {symbols}")

    for sym in symbols:
        series = _series_for_symbol(sym, limit= max(200, SMA_WINDOW + LOOKBACK_POINTS + 5))
        if not series:
            continue

        decision, info = _decide_action(series)
        if decision in ("BUY", "SELL"):
            payload = info
            msg = _format_message(sym, decision, payload)
            alerts.append({"symbol": sym, **payload, "message": msg})
            log.info(f"ALERT {sym}: {decision} — Δ={payload['delta_pct']:.2f}% last={payload['last']:.2f} SMA={payload['sma']:.2f}")
        else:
            log.info(f"No signal for {sym}: {info}")

    # publikacja do SNS
    if alerts:
        # scal czytelny tekst + JSON w treści
        human = "\n\n".join(a["message"] for a in alerts)
        subject = f"Stock Alert(s): {', '.join(a['symbol'] for a in alerts)}"
        body = human + "\n\n---\nRaw JSON:\n" + json.dumps({"alerts": alerts}, indent=2)

        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject[:100],  # limit SNS na subject
            Message=body
        )
        log.info(f"Published {len(alerts)} alert(s) to SNS.")
    else:
        log.info("No alerts to publish.")

    # zwrotka do logów / testów
    return {"alerts_count": len(alerts), "symbols_checked": len(symbols)}
