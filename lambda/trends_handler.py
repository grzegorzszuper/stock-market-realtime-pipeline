import os
import json
import boto3
import decimal
import logging
from datetime import datetime, timezone
from boto3.dynamodb.conditions import Key

# === Env config ===
DDB_TABLE       = os.environ["DYNAMODB_TABLE"]
SNS_TOPIC_ARN   = os.environ["SNS_TOPIC_ARN"]

THRESH_PCT      = float(os.getenv("THRESH_PCT", 1.5))    # próg zmiany % vs lookback
SMA_WINDOW      = int(os.getenv("SMA_WINDOW", 20))       # okno SMA
LOOKBACK_POINTS = int(os.getenv("LOOKBACK_POINTS", 15))  # ile ostatnich punktów porównujemy
MIN_POINTS      = int(os.getenv("MIN_POINTS", 20))       # min. liczba punktów
EPS_PCT         = float(os.getenv("EPS_PCT", 0.2))       # filtr szumu: |last - SMA|/SMA >= EPS

INCLUDE_JSON_FOOTER = os.getenv("INCLUDE_JSON_FOOTER", "false").lower() == "true"
LANG = os.getenv("ALERT_LANG", "pl").lower()  # "pl" lub "en"

# === Boto3 ===
dynamodb = boto3.resource("dynamodb")
table    = dynamodb.Table(DDB_TABLE)
sns      = boto3.client("sns")

# === Logging ===
log = logging.getLogger()
log.setLevel(logging.INFO)

# === Helpers ===
def _to_float(x):
    if isinstance(x, decimal.Decimal):
        return float(x)
    return float(x)

def _sma(vals, n):
    if n <= 0 or len(vals) < n:
        return None
    return sum(vals[-n:]) / n

def _iso_now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

def _distinct_symbols(limit=200):
    """Prosty scan — wystarczający dla małej skali/demo."""
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
        ScanIndexForward=False,
        Limit=limit
    )
    items = list(reversed(resp.get("Items", [])))  # rosnąco
    series = []
    for it in items:
        if "price" in it and "timestamp" in it:
            series.append((str(it["timestamp"]), _to_float(it["price"])))
    return series

def _decide_action(series):
    """
    Reguła: BUY gdy spadek <= -THRESH_PCT i last < SMA;
            SELL gdy wzrost >= +THRESH_PCT i last > SMA;
    + filtr szumu: odchyłka od SMA >= EPS_PCT.
    Zwraca: ("BUY"/"SELL", payload) lub (None, reason).
    """
    need = max(MIN_POINTS, SMA_WINDOW, LOOKBACK_POINTS + 1)
    if len(series) < need:
        return None, "too_few_points"

    prices = [p for _, p in series]
    last   = prices[-1]

    sma = _sma(prices, SMA_WINDOW)
    if sma is None or sma == 0:
        return None, "sma_unavailable"

    ref_idx = max(0, len(prices) - 1 - LOOKBACK_POINTS)
    ref = prices[ref_idx]
    if ref == 0:
        return None, "ref_zero"

    delta_pct = (last / ref - 1.0) * 100.0
    dev_pct   = abs((last - sma) / sma) * 100.0

    if dev_pct < EPS_PCT:
        return None, "near_sma_noise"

    if delta_pct <= -THRESH_PCT and last < sma:
        return "BUY",  {"action": "BUY",  "delta_pct": delta_pct, "last": last, "sma": sma, "dev_pct": dev_pct}
    if delta_pct >=  THRESH_PCT and last > sma:
        return "SELL", {"action": "SELL", "delta_pct": delta_pct, "last": last, "sma": sma, "dev_pct": dev_pct}

    return None, "no_signal"

def _format_message(symbol, action, payload):
    now = _iso_now()
    is_buy = (action == "BUY")
    if LANG == "pl":
        emoji       = "📉" if is_buy else "📈"
        action_txt  = "KUPUJ" if is_buy else "SPRZEDAJ"
        above_below = "poniżej" if is_buy else "powyżej"
        header = f"{emoji} Alert giełdowy — {symbol}\n"
        body = (
            f"⏰ {now}\n"
            f"Akcja: {action_txt}\n"
            f"Powód: {payload['delta_pct']:+.2f}% w porównaniu z ostatnimi {LOOKBACK_POINTS} pkt. "
            f"i cena {above_below} SMA{SMA_WINDOW}\n"
            f"Ostatni: {payload['last']:.2f}\n"
            f"SMA{SMA_WINDOW}: {payload['sma']:.2f} (różnica: {payload['dev_pct']:.2f}%)\n"
            f"Parametry: THRESH_PCT={THRESH_PCT}%, LOOKBACK_POINTS={LOOKBACK_POINTS}, "
            f"SMA_WINDOW={SMA_WINDOW}, MIN_POINTS={MIN_POINTS}, EPS_PCT={EPS_PCT}%"
        )
        subject = f"Alerty: {symbol}:{action_txt}"
    else:
        emoji       = "📉" if is_buy else "📈"
        action_txt  = "BUY" if is_buy else "SELL"
        above_below = "below" if is_buy else "above"
        header = f"{emoji} Stock Alert — {symbol}\n"
        body = (
            f"⏰ {now}\n"
            f"Action: {action_txt}\n"
            f"Reason: {payload['delta_pct']:+.2f}% vs last {LOOKBACK_POINTS} pt(s) and price {above_below} SMA{SMA_WINDOW}\n"
            f"Last: {payload['last']:.2f}\n"
            f"SMA{SMA_WINDOW}: {payload['sma']:.2f} (diff: {payload['dev_pct']:.2f}%)\n"
            f"Params: THRESH_PCT={THRESH_PCT}%, LOOKBACK_POINTS={LOOKBACK_POINTS}, "
            f"SMA_WINDOW={SMA_WINDOW}, MIN_POINTS={MIN_POINTS}, EPS_PCT={EPS_PCT}%"
        )
        subject = f"Alerts: {symbol}:{action_txt}"
    return header + body, subject

# === Lambda handler ===
def lambda_handler(event, context):
    log.info(
        f"Config THRESH_PCT={THRESH_PCT} LOOKBACK_POINTS={LOOKBACK_POINTS} "
        f"SMA_WINDOW={SMA_WINDOW} MIN_POINTS={MIN_POINTS} EPS_PCT={EPS_PCT} LANG={LANG} JSON_FOOTER={INCLUDE_JSON_FOOTER}"
    )

    alerts = []
    symbols = _distinct_symbols()
    log.info(f"Symbols: {symbols}")

    for sym in symbols:
        series = _series_for_symbol(sym, limit=max(200, SMA_WINDOW + LOOKBACK_POINTS + 5))
        if not series:
            continue

        decision, info = _decide_action(series)
        if decision in ("BUY", "SELL"):
            payload = info
            text, subj_part = _format_message(sym, decision, payload)
            alerts.append({"symbol": sym, **payload, "message": text, "subject_part": subj_part})
            log.info(f"ALERT {sym}: {decision} Δ={payload['delta_pct']:.2f}% last={payload['last']:.2f} SMA={payload['sma']:.2f}")
        else:
            log.info(f"No signal for {sym}: {info}")

    if alerts:
        human = "\n\n".join(a["message"] for a in alerts)
        subject = ", ".join(a["subject_part"] for a in alerts)
        body = human
        if INCLUDE_JSON_FOOTER:
            body += "\n\n---\nRaw JSON:\n" + json.dumps({"alerts": alerts}, indent=2, ensure_ascii=False)

        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject[:100],  # limit SNS
            Message=body
        )
        log.info(f"Published {len(alerts)} alert(s) to SNS.")
    else:
        log.info("No alerts to publish.")

    return {"alerts_count": len(alerts), "symbols_checked": len(symbols)}
