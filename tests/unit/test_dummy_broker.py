import pytest

from apps.api.schemas import CreateOrderRequest, OrderSide, OrderType
from pkg.brokers.dummy import DummyBroker
from pkg.domain.models import Order


@pytest.mark.asyncio
async def test_dummy_broker_executes_market_order():
    broker = DummyBroker()
    
    request = CreateOrderRequest(
        symbol="BTC/USDT",
        side=OrderSide.BUY,
        type=OrderType.MARKET,
        qty=0.01,
        limit_price=None,
        client_id="test",
        idempotency_key="test-market",
    )
    
    order = Order.from_request(request)
    result = await broker.execute(order)
    
    assert result.order_id == order.id
    assert result.symbol == "BTC/USDT"
    assert result.side == "buy"
    assert result.qty == 0.01
    assert result.filled is True
    assert 57000 < result.avg_price < 59000


@pytest.mark.asyncio
async def test_dummy_broker_executes_limit_order():
    broker = DummyBroker()
    
    request = CreateOrderRequest(
        symbol="ETH/USDT",
        side=OrderSide.SELL,
        type=OrderType.LIMIT,
        qty=1.0,
        limit_price=2500.0,
        client_id="test",
        idempotency_key="test-limit",
    )
    
    order = Order.from_request(request)
    result = await broker.execute(order)
    
    assert result.order_id == order.id
    assert result.symbol == "ETH/USDT"
    assert result.side == "sell"
    assert result.qty == 1.0
    assert result.filled is True
    assert result.avg_price >= 2500.0


@pytest.mark.asyncio
async def test_dummy_broker_cancel_order():
    broker = DummyBroker()
    
    cancelled = await broker.cancel("test-order-123")
    assert cancelled is True


@pytest.mark.asyncio
async def test_dummy_broker_get_balance():
    broker = DummyBroker()
    
    usdt_balance = await broker.get_balance("USDT")
    assert usdt_balance == 100000.0
    
    btc_balance = await broker.get_balance("BTC")
    assert btc_balance == 1.0
    
    unknown_balance = await broker.get_balance("UNKNOWN")
    assert unknown_balance == 0.0