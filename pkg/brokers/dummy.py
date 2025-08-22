import asyncio
import random
from typing import Dict

from pkg.brokers.base import BaseBroker, ExecutionResult
from pkg.domain.models import Order
from pkg.infra.logging import get_logger
from pkg.infra.metrics import FILLS_TOTAL

logger = get_logger(__name__)


class DummyBroker(BaseBroker):
    def __init__(self):
        self.prices = {
            "BTC/USDT": 58000.0,
            "ETH/USDT": 2400.0,
            "SOL/USDT": 140.0,
        }
        self.balances: Dict[str, float] = {
            "USDT": 100000.0,
            "BTC": 1.0,
            "ETH": 10.0,
            "SOL": 100.0,
        }
    
    async def execute(self, order: Order) -> ExecutionResult:
        await asyncio.sleep(0.1)
        
        base_price = self.prices.get(order.symbol, 100.0)
        slippage = random.uniform(-0.001, 0.001)
        execution_price = base_price * (1 + slippage)
        
        if order.type == "limit" and order.limit_price:
            if order.side == "buy" and execution_price > order.limit_price:
                execution_price = order.limit_price
            elif order.side == "sell" and execution_price < order.limit_price:
                execution_price = order.limit_price
        
        logger.info(
            "DummyBroker executed order",
            order_id=order.id,
            symbol=order.symbol,
            side=order.side,
            qty=order.qty,
            price=execution_price,
        )
        
        FILLS_TOTAL.inc()
        
        return ExecutionResult(
            order_id=order.id,
            symbol=order.symbol,
            side=order.side,
            qty=order.qty,
            avg_price=execution_price,
            filled=True,
        )
    
    async def cancel(self, order_id: str) -> bool:
        await asyncio.sleep(0.05)
        logger.info("DummyBroker cancelled order", order_id=order_id)
        return True
    
    async def get_balance(self, asset: str) -> float:
        return self.balances.get(asset, 0.0)