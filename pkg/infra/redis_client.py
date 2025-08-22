from typing import Optional

import redis.asyncio as redis

from pkg.infra.settings import get_settings

_redis_client: Optional[redis.Redis] = None


async def get_redis_client() -> redis.Redis:
    global _redis_client
    
    if _redis_client is None:
        settings = get_settings()
        _redis_client = redis.from_url(
            settings.redis_url,
            encoding="utf-8",
            decode_responses=True,
        )
    
    return _redis_client


async def close_redis():
    global _redis_client
    
    if _redis_client:
        await _redis_client.close()
        _redis_client = None