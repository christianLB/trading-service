from typing import List, Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from pkg.domain.models import Fill, Order, Position


class OrderRepository:
    def __init__(self, session: AsyncSession):
        self.session = session
    
    async def create(self, order: Order) -> Order:
        self.session.add(order)
        await self.session.commit()
        await self.session.refresh(order)
        return order
    
    async def update(self, order: Order) -> Order:
        await self.session.commit()
        await self.session.refresh(order)
        return order
    
    async def get_by_id(self, order_id: str) -> Optional[Order]:
        result = await self.session.execute(
            select(Order).where(Order.id == order_id)
        )
        return result.scalar_one_or_none()
    
    async def get_by_idempotency_key(self, key: str) -> Optional[Order]:
        result = await self.session.execute(
            select(Order).where(Order.idempotency_key == key)
        )
        return result.scalar_one_or_none()


class FillRepository:
    def __init__(self, session: AsyncSession):
        self.session = session
    
    async def create(self, fill: Fill) -> Fill:
        self.session.add(fill)
        await self.session.commit()
        await self.session.refresh(fill)
        return fill
    
    async def get_by_order_id(self, order_id: str) -> List[Fill]:
        result = await self.session.execute(
            select(Fill).where(Fill.order_id == order_id)
        )
        return list(result.scalars().all())


class PositionRepository:
    def __init__(self, session: AsyncSession):
        self.session = session
    
    async def get_or_create(self, symbol: str) -> Position:
        result = await self.session.execute(
            select(Position).where(Position.symbol == symbol)
        )
        position = result.scalar_one_or_none()
        
        if not position:
            position = Position(symbol=symbol)
            self.session.add(position)
            await self.session.commit()
            await self.session.refresh(position)
        
        return position
    
    async def update(self, position: Position) -> Position:
        await self.session.commit()
        await self.session.refresh(position)
        return position
    
    async def get_all_open(self) -> List[Position]:
        result = await self.session.execute(
            select(Position).where(Position.qty != 0)
        )
        return list(result.scalars().all())
    
    async def get_total_notional(self) -> float:
        positions = await self.get_all_open()
        return sum(abs(pos.qty * pos.avg_price) for pos in positions)