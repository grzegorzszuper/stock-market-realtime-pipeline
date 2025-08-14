import os, json, boto3, decimal
from boto3.dynamodb.conditions import Key

DDB_TABLE     = os.environ["DYNAMODB_TABLE"]
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]

dynamodb = boto3.resource("dynamodb")
table    = dynamodb.Table(DDB_TABLE)
sns      = boto3.client("sns")

SORT_KEY = "timestamp"  # jeśli masz inną nazwę SK -> podmień tutaj

def _to_float(x):
    if isinstance(x, decimal.Decimal):
        return float(x)
    return float(x)

def _sma(vals, n):
    if len(vals) < n:
        return None
    return sum(vals[-n:]) / n

def _distinct_symbols(limit=200):
    # prosto: scan z projekcją; OK przy małych wolumenach
    syms = set()
    resp = table.scan(ProjectionExpression="#s", ExpressionAttributeNames={"#s": "symbol"})
    syms.update(i["symbol"] for i in resp.get("Items", []) if "symbol" in i)
    while "LastEvaluatedKey" in resp and len(syms) < limit:
        resp = table.scan(
            ProjectionExpression="#s",
            ExpressionAttributeNames={"#s": "symbol"},
            ExclusiveStartKey=resp["LastEvaluatedKey"]
        )
        syms.update(i["symbol"] for i in resp.get("Items", []) if "symbol" in i)
    return list(syms)[:limit]

def _prices_for_symbol(sym, limit=50):
    # zakładamy klucz partycjonujący symbol + sort key = timestamp (ISO)
    resp = table.query(
        KeyConditionExpression=Key("symbol").eq(sym),
        ScanIndexForward=False,  # najnowsze najpierw
        Limit=limit
    )
    items = list(reversed(resp.get("Items", [])))  # teraz rosnąco po czasie
    return [_to_float(i["price"]) for i in items if "price" in i]

def lambda_handler(event, context):
    alerts = []

    for sym in _distinct_symbols():
        prices = _prices_for_symbol(sym, 50)

        if len(prices) < 21:
            continue

        sma5_prev  = _sma(prices[:-1], 5)
        sma20_prev = _sma(prices[:-1], 20)
        sma5_now   = _sma(prices, 5)
        sma20_now  = _sma(prices, 20)
        if sma5_prev is None or sma20_prev is None:
            continue

        crossed_up   = sma5_prev <= sma20_prev and sma5_now > sma20_now
        crossed_down = sma5_prev >= sma20_prev and sma5_now < sma20_now

        if crossed_up or crossed_down:
            direction = "GOLDEN" if crossed_up else "DEATH"
            msg = f"[{sym}] SMA5 vs SMA20 cross: {direction} — last={prices[-1]:.2f}"
            alerts.append({"symbol": sym, "type": direction, "last": prices[-1]})

    if alerts:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject="Stock trends alert(s)",
            Message=json.dumps({"alerts": alerts}, indent=2)
        )

    return {"alerts": alerts}
