from datetime import datetime, timedelta
from typing import Tuple

from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from apps.api.schemas import OrderSide
from pkg.domain.models import Fill, Order
from pkg.domain.repositories import PositionRepository
from pkg.infra.settings import get_settings


class RiskEngine:
    def __init__(self):
        self.settings = get_settings()
        self.whitelist = {"BTC/USDT", "ETH/USDT", "SOL/USDT"}
    
    async def check_order(self, order: Order, session: AsyncSession) -> Tuple[bool, str]:
        if order.symbol not in self.whitelist:
            return False, f"Symbol {order.symbol} not in whitelist"
        
        notional = order.qty * (order.limit_price or self._get_dummy_price(order.symbol))
        
        position_repo = PositionRepository(session)
        current_notional = await position_repo.get_total_notional()
        
        if current_notional + notional > self.settings.max_pos_usd:
            return False, f"Position limit exceeded: {current_notional + notional} > {self.settings.max_pos_usd}"
        
        daily_loss = await self._get_daily_loss(session)
        if daily_loss >= self.settings.max_daily_loss_usd:
            return False, f"Daily loss limit reached: {daily_loss}"
        
        return True, "OK"
    
    async def _get_daily_loss(self, session: AsyncSession) -> float:
        start_of_day = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
        
        result = await session.execute(
            select(func.sum(Fill.qty * Fill.price))
            .where(Fill.timestamp >= start_of_day)
            .where(Fill.side == OrderSide.SELL)
        )
        sells = result.scalar() or 0
        
        result = await session.execute(
            select(func.sum(Fill.qty * Fill.price))
            .where(Fill.timestamp >= start_of_day)
            .where(Fill.side == OrderSide.BUY)
        )
        buys = result.scalar() or 0
        
        return max(0, buys - sells)
    
    def _get_dummy_price(self, symbol: str) -> float:
        prices = {
            "BTC/USDT": 58000.0,
            "ETH/USDT": 2400.0,
            "SOL/USDT": 140.0,
        }
        return prices.get(symbol, 100.0)