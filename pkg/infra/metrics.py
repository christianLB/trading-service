from prometheus_client import Counter, Histogram, Gauge

ORDERS_TOTAL = Counter("orders_total", "Total number of orders created")
FILLS_TOTAL = Counter("fills_total", "Total number of fills executed")
RISK_BLOCKS_TOTAL = Counter("risk_blocks_total", "Total number of orders blocked by risk")

ORDER_LATENCY = Histogram("order_latency_seconds", "Order processing latency")
POSITION_NOTIONAL = Gauge("position_notional_usd", "Total position notional in USD")


def setup_metrics():
    # Metrics without labels don't need initialization
    pass