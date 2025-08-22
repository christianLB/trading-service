"""CCXT broker implementation for real exchange integration."""
import asyncio
from datetime import datetime
from typing import Any, Dict, List, Optional

import ccxt.async_support as ccxt
from pydantic import BaseModel

from pkg.brokers.base import BaseBroker, ExecutionResult
from pkg.domain.models import Order, OrderStatus, OrderSide, OrderType
from pkg.infra.logging import get_logger
from pkg.infra.settings import get_settings

logger = get_logger(__name__)


class CCXTConfig(BaseModel):
    """Configuration for CCXT broker."""
    exchange_id: str = "binance"
    api_key: Optional[str] = None
    api_secret: Optional[str] = None
    testnet: bool = True
    rate_limit: int = 50  # requests per second
    options: Dict[str, Any] = {}


class CCXTBroker(BaseBroker):
    """Broker implementation using CCXT for real exchange integration."""
    
    def __init__(self, config: Optional[CCXTConfig] = None):
        """Initialize CCXT broker with configuration."""
        self.config = config or self._get_default_config()
        self.exchange = None
        self._initialized = False
        self._rate_limiter = asyncio.Semaphore(self.config.rate_limit)
    
    def _get_default_config(self) -> CCXTConfig:
        """Get default configuration from settings."""
        settings = get_settings()
        
        config = CCXTConfig(
            exchange_id=settings.exchange,
            api_key=settings.api_key,
            api_secret=settings.api_secret,
            testnet=settings.app_env != "prod",
        )
        
        # Set testnet options for Binance
        if config.testnet and config.exchange_id == "binance":
            config.options = {
                "defaultType": "future",  # or 'spot', 'margin', 'future', 'option'
                "testnet": True,
                "urls": {
                    "api": {
                        "spot": "https://testnet.binance.vision",
                        "future": "https://testnet.binancefuture.com",
                    }
                }
            }
        
        return config
    
    async def initialize(self):
        """Initialize the exchange connection."""
        if self._initialized:
            return
        
        try:
            # Get exchange class
            exchange_class = getattr(ccxt, self.config.exchange_id)
            
            # Create exchange instance
            self.exchange = exchange_class({
                "apiKey": self.config.api_key,
                "secret": self.config.api_secret,
                "enableRateLimit": True,
                "rateLimit": 1000 // self.config.rate_limit,  # Convert to ms between requests
                "options": self.config.options,
            })
            
            # Load markets
            await self.exchange.load_markets()
            
            self._initialized = True
            logger.info(
                "CCXT broker initialized",
                exchange=self.config.exchange_id,
                testnet=self.config.testnet,
                markets_count=len(self.exchange.markets),
            )
            
        except Exception as e:
            logger.error(
                "Failed to initialize CCXT broker",
                exchange=self.config.exchange_id,
                error=str(e),
            )
            raise
    
    async def _ensure_initialized(self):
        """Ensure broker is initialized before operations."""
        if not self._initialized:
            await self.initialize()
    
    async def execute(self, order: Order) -> ExecutionResult:
        """Execute an order on the exchange."""
        await self._ensure_initialized()
        
        async with self._rate_limiter:
            try:
                # Prepare order parameters
                symbol = order.symbol
                order_type = order.type.value.lower()
                side = order.side.value.lower()
                amount = float(order.qty)
                
                params = {}
                if order.type == OrderType.LIMIT and order.limit_price:
                    price = float(order.limit_price)
                else:
                    price = None
                
                # Create order on exchange
                logger.info(
                    "Creating order on exchange",
                    symbol=symbol,
                    side=side,
                    type=order_type,
                    amount=amount,
                    price=price,
                )
                
                result = await self.exchange.create_order(
                    symbol=symbol,
                    type=order_type,
                    side=side,
                    amount=amount,
                    price=price,
                    params=params,
                )
                
                # Extract execution details
                exchange_order_id = result.get("id")
                filled_qty = result.get("filled", 0)
                avg_price = result.get("average") or result.get("price", 0)
                status = result.get("status", "open")
                
                # Map exchange status to our status
                if status == "closed":
                    order_status = OrderStatus.FILLED
                elif status == "canceled":
                    order_status = OrderStatus.CANCELLED
                elif status == "expired":
                    order_status = OrderStatus.CANCELLED
                else:
                    order_status = OrderStatus.PENDING
                
                logger.info(
                    "Order executed on exchange",
                    exchange_order_id=exchange_order_id,
                    filled_qty=filled_qty,
                    avg_price=avg_price,
                    status=status,
                )
                
                return ExecutionResult(
                    order_id=order.id,
                    symbol=order.symbol,
                    side=order.side.value,
                    qty=filled_qty,
                    avg_price=avg_price,
                    filled=order_status == OrderStatus.FILLED,
                )
                
            except ccxt.NetworkError as e:
                logger.error("Network error executing order", error=str(e))
                raise Exception(f"Network error: {str(e)}")
            
            except ccxt.ExchangeError as e:
                logger.error("Exchange error executing order", error=str(e))
                raise Exception(f"Exchange error: {str(e)}")
            
            except Exception as e:
                logger.error("Unexpected error executing order", error=str(e))
                raise
    
    async def cancel(self, order_id: str) -> bool:
        """Cancel an order on the exchange."""
        await self._ensure_initialized()
        
        async with self._rate_limiter:
            try:
                # Need to find the symbol for this order
                # In production, we'd look this up from our database
                # For now, we'll require passing symbol separately
                logger.warning("Cancel order requires symbol lookup - not fully implemented")
                return False
                
            except ccxt.OrderNotFound:
                logger.warning("Order not found for cancellation", order_id=order_id)
                return False
                
            except Exception as e:
                logger.error("Error cancelling order", order_id=order_id, error=str(e))
                return False
    
    async def get_balance(self, asset: str) -> float:
        """Get account balance from the exchange."""
        await self._ensure_initialized()
        
        async with self._rate_limiter:
            try:
                balance = await self.exchange.fetch_balance()
                
                # Extract balance for specific asset
                if asset in balance:
                    details = balance[asset]
                    if isinstance(details, dict) and "free" in details:
                        free_amount = details["free"] or 0.0
                        logger.info("Balance fetched", asset=asset, amount=free_amount)
                        return float(free_amount)
                
                logger.warning("Asset not found in balance", asset=asset)
                return 0.0
                
            except Exception as e:
                logger.error("Error fetching balance", error=str(e))
                return 0.0
    
    async def get_order_status(self, order_id: str, symbol: str) -> Optional[Dict[str, Any]]:
        """Get order status from the exchange."""
        await self._ensure_initialized()
        
        async with self._rate_limiter:
            try:
                order = await self.exchange.fetch_order(order_id, symbol)
                
                return {
                    "id": order.get("id"),
                    "status": order.get("status"),
                    "filled": order.get("filled", 0),
                    "remaining": order.get("remaining", 0),
                    "average": order.get("average") or order.get("price"),
                    "timestamp": order.get("timestamp"),
                }
                
            except ccxt.OrderNotFound:
                logger.warning("Order not found", order_id=order_id)
                return None
                
            except Exception as e:
                logger.error("Error fetching order status", order_id=order_id, error=str(e))
                return None
    
    async def get_ticker(self, symbol: str) -> Optional[Dict[str, float]]:
        """Get current ticker data for a symbol."""
        await self._ensure_initialized()
        
        async with self._rate_limiter:
            try:
                ticker = await self.exchange.fetch_ticker(symbol)
                
                return {
                    "bid": ticker.get("bid"),
                    "ask": ticker.get("ask"),
                    "last": ticker.get("last"),
                    "volume": ticker.get("baseVolume"),
                }
                
            except Exception as e:
                logger.error("Error fetching ticker", symbol=symbol, error=str(e))
                return None
    
    async def close(self):
        """Close the exchange connection."""
        if self.exchange:
            await self.exchange.close()
            self._initialized = False
            logger.info("CCXT broker closed")
    
    def __del__(self):
        """Cleanup on deletion."""
        if self.exchange and not self.exchange.closed:
            try:
                asyncio.create_task(self.close())
            except:
                pass