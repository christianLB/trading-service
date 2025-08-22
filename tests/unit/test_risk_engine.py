import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from apps.api.schemas import CreateOrderRequest, OrderSide, OrderType
from pkg.domain.models import Order, Position
from pkg.risk.engine import RiskEngine


@pytest.mark.asyncio
async def test_risk_engine_allows_valid_order(db_session: AsyncSession):
    risk_engine = RiskEngine()
    
    request = CreateOrderRequest(
        symbol="BTC/USDT",
        side=OrderSide.BUY,
        type=OrderType.MARKET,
        qty=0.01,
        limit_price=None,
        client_id="test",
        idempotency_key="test-123",
    )
    
    order = Order.from_request(request)
    is_allowed, reason = await risk_engine.check_order(order, db_session)
    
    assert is_allowed is True
    assert reason == "OK"


@pytest.mark.asyncio
async def test_risk_engine_blocks_invalid_symbol(db_session: AsyncSession):
    risk_engine = RiskEngine()
    
    request = CreateOrderRequest(
        symbol="DOGE/USDT",
        side=OrderSide.BUY,
        type=OrderType.MARKET,
        qty=0.01,
        limit_price=None,
        client_id="test",
        idempotency_key="test-456",
    )
    
    order = Order.from_request(request)
    is_allowed, reason = await risk_engine.check_order(order, db_session)
    
    assert is_allowed is False
    assert "not in whitelist" in reason


@pytest.mark.asyncio
async def test_risk_engine_blocks_position_limit(db_session: AsyncSession):
    risk_engine = RiskEngine()
    risk_engine.settings.max_pos_usd = 1000.0
    
    position = Position(symbol="BTC/USDT", qty=0.02, avg_price=58000.0)
    db_session.add(position)
    await db_session.commit()
    
    request = CreateOrderRequest(
        symbol="BTC/USDT",
        side=OrderSide.BUY,
        type=OrderType.MARKET,
        qty=0.01,
        limit_price=None,
        client_id="test",
        idempotency_key="test-789",
    )
    
    order = Order.from_request(request)
    is_allowed, reason = await risk_engine.check_order(order, db_session)
    
    assert is_allowed is False
    assert "Position limit exceeded" in reason