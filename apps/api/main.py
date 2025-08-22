from contextlib import asynccontextmanager
from typing import AsyncGenerator

from fastapi import FastAPI
from prometheus_client import REGISTRY, generate_latest
from starlette.responses import PlainTextResponse

from apps.api.routers import health, orders, positions
from pkg.infra.logging import setup_logging
from pkg.infra.metrics import setup_metrics


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator:
    setup_logging()
    setup_metrics()
    yield


app = FastAPI(
    title="Trading Service",
    version="0.1.0",
    description="Deterministic trading microservice",
    lifespan=lifespan,
)

app.include_router(health.router, tags=["health"])
app.include_router(orders.router, prefix="/orders", tags=["orders"])
app.include_router(positions.router, prefix="/positions", tags=["positions"])


@app.get("/metrics", response_class=PlainTextResponse)
async def metrics() -> PlainTextResponse:
    return PlainTextResponse(generate_latest(REGISTRY))