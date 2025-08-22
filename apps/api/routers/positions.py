from typing import Annotated, List

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from apps.api.deps import get_db, verify_token
from apps.api.schemas import PositionResponse
from pkg.domain.repositories import PositionRepository

router = APIRouter()


@router.get("", response_model=List[PositionResponse])
async def get_positions(
    token: Annotated[str, Depends(verify_token)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> List[PositionResponse]:
    repo = PositionRepository(db)
    positions = await repo.get_all_open()
    
    # Get current prices from DummyBroker for PnL calculation
    from pkg.brokers.dummy import DummyBroker
    broker = DummyBroker()
    
    result = []
    for pos in positions:
        current_price = broker.prices.get(pos.symbol, pos.avg_price)
        pnl = (current_price - pos.avg_price) * pos.qty
        
        result.append(
            PositionResponse(
                symbol=pos.symbol,
                qty=pos.qty,
                avg_price=pos.avg_price,
                notional=pos.notional,
                pnl=pnl,
                updated_at=pos.updated_at,
            )
        )
    
    return result