from typing import Annotated

from fastapi import Depends, HTTPException, Header
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession

from pkg.infra.database import get_db_session
from pkg.infra.settings import get_settings

security = HTTPBearer()


async def verify_token(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)]
) -> str:
    settings = get_settings()
    if credentials.credentials != settings.api_token:
        raise HTTPException(status_code=403, detail="Invalid authentication token")
    return credentials.credentials


async def get_db() -> AsyncSession:
    async with get_db_session() as session:
        yield session