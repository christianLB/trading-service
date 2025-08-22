from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from apps.api.deps import get_db, verify_token
from apps.api.schemas import (
    CreateOrderRequest,
    CreateOrderResponse,
    ErrorResponse,
    OrderResponse,
    OrderStatus,
)
from pkg.brokers.dummy import DummyBroker
from pkg.domain.models import Fill, Order
from pkg.domain.repositories import FillRepository, OrderRepository, PositionRepository
from pkg.infra.metrics import FILLS_TOTAL, ORDERS_TOTAL, RISK_BLOCKS_TOTAL
from pkg.infra.webhooks import send_webhook
from pkg.risk.engine import RiskEngine

router = APIRouter()


@router.post(
    "",
    response_model=CreateOrderResponse,
    responses={
        422: {"model": ErrorResponse, "description": "Risk validation failed"},
        403: {"model": ErrorResponse, "description": "Authentication failed"},
    },
)
async def create_order(
    request: CreateOrderRequest,
    token: Annotated[str, Depends(verify_token)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> CreateOrderResponse:
    risk_engine = RiskEngine()
    broker = DummyBroker()
    repo = OrderRepository(db)
    
    existing = await repo.get_by_idempotency_key(request.idempotency_key)
    if existing:
        return CreateOrderResponse(order_id=existing.id, status=existing.status)
    
    order = Order.from_request(request)
    
    is_allowed, reason = await risk_engine.check_order(order, db)
    if not is_allowed:
        RISK_BLOCKS_TOTAL.inc()
        raise HTTPException(status_code=422, detail=f"Risk blocked: {reason}")
    
    order = await repo.create(order)
    ORDERS_TOTAL.inc()
    
    # Execute order via broker
    execution = await broker.execute(order)
    
    # Update order with execution details
    order.status = OrderStatus.FILLED
    order.filled_qty = execution.qty
    order.avg_price = execution.avg_price
    await repo.update(order)
    
    # Create fill record
    fill_repo = FillRepository(db)
    fill = Fill(
        order_id=order.id,
        symbol=order.symbol,
        side=order.side,
        qty=execution.qty,
        price=execution.avg_price,
        client_id=order.client_id,
    )
    await fill_repo.create(fill)
    FILLS_TOTAL.inc()
    
    # Update position
    position_repo = PositionRepository(db)
    position = await position_repo.get_or_create(order.symbol)
    
    if order.side.value == "buy":
        # Calculate new average price for buy
        new_total_qty = position.qty + execution.qty
        if new_total_qty != 0:
            new_avg_price = ((position.qty * position.avg_price) + (execution.qty * execution.avg_price)) / new_total_qty
            position.qty = new_total_qty
            position.avg_price = new_avg_price
    else:  # sell
        position.qty -= execution.qty
        # If position is closed, reset avg_price
        if abs(position.qty) < 0.00001:
            position.qty = 0
            position.avg_price = 0
    
    position.notional = abs(position.qty * position.avg_price)
    await position_repo.update(position)
    
    # Send webhook
    await send_webhook("order_filled", {
        "orderId": order.id,
        "symbol": order.symbol,
        "filledQty": order.filled_qty,
        "avgPrice": order.avg_price,
    })
    
    return CreateOrderResponse(order_id=order.id, status=order.status)


@router.get("/{order_id}", response_model=OrderResponse)
async def get_order(
    order_id: str,
    token: Annotated[str, Depends(verify_token)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> OrderResponse:
    repo = OrderRepository(db)
    order = await repo.get_by_id(order_id)
    
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    
    return OrderResponse(
        order_id=order.id,
        symbol=order.symbol,
        side=order.side,
        type=order.type,
        qty=order.qty,
        limit_price=order.limit_price,
        filled_qty=order.filled_qty,
        avg_price=order.avg_price,
        status=order.status,
        client_id=order.client_id,
        created_at=order.created_at,
        updated_at=order.updated_at,
    )