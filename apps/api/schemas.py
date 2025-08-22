from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


class OrderSide(str, Enum):
    BUY = "buy"
    SELL = "sell"


class OrderType(str, Enum):
    MARKET = "market"
    LIMIT = "limit"


class OrderStatus(str, Enum):
    ACCEPTED = "accepted"
    PENDING = "pending"
    FILLED = "filled"
    REJECTED = "rejected"
    CANCELLED = "cancelled"


class CreateOrderRequest(BaseModel):
    symbol: str = Field(..., example="BTC/USDT")
    side: OrderSide
    type: OrderType
    qty: float = Field(..., gt=0, example=0.01)
    limit_price: Optional[float] = Field(None, alias="limitPrice", gt=0)
    client_id: str = Field(..., alias="clientId", example="k2600x-admin")
    idempotency_key: str = Field(..., alias="idempotencyKey")

    class Config:
        populate_by_name = True


class CreateOrderResponse(BaseModel):
    order_id: str = Field(..., alias="orderId")
    status: OrderStatus

    class Config:
        populate_by_name = True


class OrderResponse(BaseModel):
    order_id: str = Field(..., alias="orderId")
    symbol: str
    side: OrderSide
    type: OrderType
    qty: float
    limit_price: Optional[float] = Field(None, alias="limitPrice")
    filled_qty: float = Field(..., alias="filledQty")
    avg_price: Optional[float] = Field(None, alias="avgPrice")
    status: OrderStatus
    client_id: str = Field(..., alias="clientId")
    created_at: datetime = Field(..., alias="createdAt")
    updated_at: datetime = Field(..., alias="updatedAt")

    class Config:
        populate_by_name = True


class PositionResponse(BaseModel):
    symbol: str
    qty: float
    avg_price: float = Field(..., alias="avgPrice")
    notional: float
    pnl: float
    updated_at: datetime = Field(..., alias="updatedAt")

    class Config:
        populate_by_name = True


class HealthResponse(BaseModel):
    status: str
    timestamp: datetime
    database: str
    redis: str


class ErrorResponse(BaseModel):
    error: str
    message: str
    timestamp: datetime