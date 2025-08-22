from functools import lru_cache
from typing import Optional

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")
    
    app_name: str = "trading-service"
    app_env: str = "dev"
    api_port: int = 8080
    
    database_url: str = "postgresql+asyncpg://postgres:postgres@db:5432/trading"
    redis_url: str = "redis://redis:6379/0"
    
    broker: str = "dummy"
    exchange: str = "binance"
    api_key: Optional[str] = None
    api_secret: Optional[str] = None
    
    api_token: str = "change_me"
    
    webhook_url: Optional[str] = None
    webhook_secret: str = "change_me"
    
    max_pos_usd: float = 5000.0
    max_daily_loss_usd: float = 500.0
    
    log_level: str = "INFO"


@lru_cache()
def get_settings() -> Settings:
    return Settings()