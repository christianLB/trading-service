from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional

from pkg.domain.models import Order


@dataclass
class ExecutionResult:
    order_id: str
    symbol: str
    side: str
    qty: float
    avg_price: float
    filled: bool = True


class BaseBroker(ABC):
    @abstractmethod
    async def execute(self, order: Order) -> ExecutionResult:
        pass
    
    @abstractmethod
    async def cancel(self, order_id: str) -> bool:
        pass
    
    @abstractmethod
    async def get_balance(self, asset: str) -> float:
        pass