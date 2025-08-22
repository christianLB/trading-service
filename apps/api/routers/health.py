from datetime import datetime

from fastapi import APIRouter
from sqlalchemy import text

from apps.api.schemas import HealthResponse
from pkg.infra.database import get_db_session
from pkg.infra.redis_client import get_redis_client

router = APIRouter()


@router.get("/healthz", response_model=HealthResponse)
async def health_check() -> HealthResponse:
    db_status = "unhealthy"
    redis_status = "unhealthy"
    
    try:
        async with get_db_session() as session:
            result = await session.execute(text("SELECT 1"))
            if result.scalar() == 1:
                db_status = "healthy"
    except Exception:
        pass
    
    try:
        redis = await get_redis_client()
        await redis.ping()
        redis_status = "healthy"
    except Exception:
        pass
    
    return HealthResponse(
        status="healthy" if db_status == "healthy" and redis_status == "healthy" else "degraded",
        timestamp=datetime.utcnow(),
        database=db_status,
        redis=redis_status,
    )