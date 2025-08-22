"""
SQLAlchemy models derived from OpenAPI contract (CONTRACT-FIRST approach).
All models match the OpenAPI schemas defined in contracts/openapi.yaml.
"""
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, Enum, Float, String, Text, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from apps.api.schemas import CreateOrderRequest, OrderSide, OrderStatus, OrderType


class Base(DeclarativeBase):
    pass


class Order(Base):
    """Order model matching OpenAPI OrderResponse schema."""
    __tablename__ = "orders"
    
    # Using order_id to match OpenAPI field naming (orderId in JSON)
    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: f"ord_{uuid.uuid4().hex[:8]}")
    symbol: Mapped[str] = mapped_column(String, nullable=False, index=True)
    side: Mapped[OrderSide] = mapped_column(Enum(OrderSide), nullable=False)
    type: Mapped[OrderType] = mapped_column(Enum(OrderType), nullable=False)
    qty: Mapped[float] = mapped_column(Float, nullable=False)
    limit_price: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    filled_qty: Mapped[float] = mapped_column(Float, default=0.0)
    avg_price: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    status: Mapped[OrderStatus] = mapped_column(Enum(OrderStatus), default=OrderStatus.ACCEPTED)
    client_id: Mapped[str] = mapped_column(String, nullable=False)
    idempotency_key: Mapped[str] = mapped_column(String, unique=True, nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())
    
    @classmethod
    def from_request(cls, request: CreateOrderRequest) -> "Order":
        """Create an Order from an API request following the contract."""
        return cls(
            symbol=request.symbol,
            side=request.side,
            type=request.type,
            qty=request.qty,
            limit_price=request.limit_price,
            client_id=request.client_id,
            idempotency_key=request.idempotency_key,
            status=OrderStatus.ACCEPTED,  # Initial status per contract
        )


class Fill(Base):
    """Fill model for order executions, supports webhook order_filled event."""
    __tablename__ = "fills"
    
    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: f"fill_{uuid.uuid4().hex[:8]}")
    order_id: Mapped[str] = mapped_column(String, nullable=False, index=True)
    symbol: Mapped[str] = mapped_column(String, nullable=False)
    side: Mapped[OrderSide] = mapped_column(Enum(OrderSide), nullable=False)
    qty: Mapped[float] = mapped_column(Float, nullable=False)  # filled_qty in webhook
    price: Mapped[float] = mapped_column(Float, nullable=False)  # avg_price in webhook
    client_id: Mapped[str] = mapped_column(String, nullable=False)  # For audit trail
    timestamp: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())  # ts in webhook


class Position(Base):
    """Position model matching OpenAPI PositionResponse schema."""
    __tablename__ = "positions"
    
    symbol: Mapped[str] = mapped_column(String, primary_key=True)
    qty: Mapped[float] = mapped_column(Float, default=0.0)
    avg_price: Mapped[float] = mapped_column(Float, default=0.0)
    notional: Mapped[float] = mapped_column(Float, default=0.0)  # Position value
    pnl: Mapped[float] = mapped_column(Float, default=0.0)  # Unrealized P&L
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())


class RiskMetrics(Base):
    """Risk metrics for tracking daily limits and position limits."""
    __tablename__ = "risk_metrics"
    
    date: Mapped[str] = mapped_column(String, primary_key=True)  # YYYY-MM-DD format
    daily_loss_usd: Mapped[float] = mapped_column(Float, default=0.0)
    total_position_usd: Mapped[float] = mapped_column(Float, default=0.0)
    risk_blocks_count: Mapped[int] = mapped_column(Float, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())


class WebhookLog(Base):
    """Webhook delivery tracking for reliability monitoring."""
    __tablename__ = "webhook_logs"
    
    id: Mapped[str] = mapped_column(String, primary_key=True, default=lambda: f"wh_{uuid.uuid4().hex[:8]}")
    event: Mapped[str] = mapped_column(String, nullable=False)  # e.g., "order_filled"
    url: Mapped[str] = mapped_column(String, nullable=False)
    payload: Mapped[str] = mapped_column(Text, nullable=False)  # JSON payload
    signature: Mapped[str] = mapped_column(String, nullable=False)  # HMAC signature
    status_code: Mapped[Optional[int]] = mapped_column(Float, nullable=True)
    response: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    retry_count: Mapped[int] = mapped_column(Float, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())