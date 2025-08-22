"""Unit tests for CCXT broker."""
import pytest
from unittest.mock import AsyncMock, MagicMock, patch

from pkg.brokers.ccxt_broker import CCXTBroker, CCXTConfig
from pkg.domain.models import Order, OrderSide, OrderType


@pytest.mark.unit
@pytest.mark.asyncio
class TestCCXTBroker:
    """Test CCXT broker functionality."""
    
    @pytest.fixture
    def config(self):
        """Test configuration."""
        return CCXTConfig(
            exchange_id="binance",
            api_key="test_key",
            api_secret="test_secret",
            testnet=True,
        )
    
    @pytest.fixture
    def order(self):
        """Test order."""
        return Order(
            id="test_order_123",
            symbol="BTC/USDT",
            side=OrderSide.BUY,
            type=OrderType.MARKET,
            qty=0.01,
            client_id="test_client",
        )
    
    async def test_initialization(self, config):
        """Test broker initialization."""
        with patch("ccxt.async_support.binance") as mock_exchange_class:
            mock_exchange = AsyncMock()
            mock_exchange.load_markets = AsyncMock()
            mock_exchange.markets = {"BTC/USDT": {}}
            mock_exchange_class.return_value = mock_exchange
            
            broker = CCXTBroker(config)
            await broker.initialize()
            
            assert broker._initialized is True
            mock_exchange.load_markets.assert_called_once()
    
    async def test_execute_market_order(self, config, order):
        """Test executing a market order."""
        with patch("ccxt.async_support.binance") as mock_exchange_class:
            mock_exchange = AsyncMock()
            mock_exchange.load_markets = AsyncMock()
            mock_exchange.create_order = AsyncMock(return_value={
                "id": "exchange_order_123",
                "filled": 0.01,
                "average": 58000.0,
                "status": "closed",
            })
            mock_exchange_class.return_value = mock_exchange
            
            broker = CCXTBroker(config)
            result = await broker.execute(order)
            
            assert result.order_id == "test_order_123"
            assert result.qty == 0.01
            assert result.avg_price == 58000.0
            assert result.filled is True
            
            mock_exchange.create_order.assert_called_once_with(
                symbol="BTC/USDT",
                type="market",
                side="buy",
                amount=0.01,
                price=None,
                params={},
            )
    
    async def test_execute_limit_order(self, config):
        """Test executing a limit order."""
        limit_order = Order(
            id="test_limit_123",
            symbol="ETH/USDT",
            side=OrderSide.SELL,
            type=OrderType.LIMIT,
            qty=0.5,
            limit_price=3000.0,
            client_id="test_client",
        )
        
        with patch("ccxt.async_support.binance") as mock_exchange_class:
            mock_exchange = AsyncMock()
            mock_exchange.load_markets = AsyncMock()
            mock_exchange.create_order = AsyncMock(return_value={
                "id": "exchange_limit_456",
                "filled": 0.5,
                "average": 3000.0,
                "status": "closed",
            })
            mock_exchange_class.return_value = mock_exchange
            
            broker = CCXTBroker(config)
            result = await broker.execute(limit_order)
            
            assert result.qty == 0.5
            assert result.avg_price == 3000.0
            
            mock_exchange.create_order.assert_called_once_with(
                symbol="ETH/USDT",
                type="limit",
                side="sell",
                amount=0.5,
                price=3000.0,
                params={},
            )
    
    async def test_get_balance(self, config):
        """Test getting account balance."""
        with patch("ccxt.async_support.binance") as mock_exchange_class:
            mock_exchange = AsyncMock()
            mock_exchange.load_markets = AsyncMock()
            mock_exchange.fetch_balance = AsyncMock(return_value={
                "BTC": {"free": 1.5, "used": 0.5, "total": 2.0},
                "USDT": {"free": 10000.0, "used": 5000.0, "total": 15000.0},
            })
            mock_exchange_class.return_value = mock_exchange
            
            broker = CCXTBroker(config)
            
            btc_balance = await broker.get_balance("BTC")
            assert btc_balance == 1.5
            
            usdt_balance = await broker.get_balance("USDT")
            assert usdt_balance == 10000.0
            
            # Test non-existent asset
            eth_balance = await broker.get_balance("ETH")
            assert eth_balance == 0.0
    
    async def test_get_ticker(self, config):
        """Test getting ticker data."""
        with patch("ccxt.async_support.binance") as mock_exchange_class:
            mock_exchange = AsyncMock()
            mock_exchange.load_markets = AsyncMock()
            mock_exchange.fetch_ticker = AsyncMock(return_value={
                "bid": 57900.0,
                "ask": 58100.0,
                "last": 58000.0,
                "baseVolume": 12345.67,
            })
            mock_exchange_class.return_value = mock_exchange
            
            broker = CCXTBroker(config)
            ticker = await broker.get_ticker("BTC/USDT")
            
            assert ticker["bid"] == 57900.0
            assert ticker["ask"] == 58100.0
            assert ticker["last"] == 58000.0
            assert ticker["volume"] == 12345.67
    
    async def test_error_handling(self, config, order):
        """Test error handling in order execution."""
        import ccxt.async_support as ccxt_async
        
        with patch("ccxt.async_support.binance") as mock_exchange_class:
            mock_exchange = AsyncMock()
            mock_exchange.load_markets = AsyncMock()
            
            # Simulate network error
            mock_exchange.create_order = AsyncMock(
                side_effect=ccxt_async.NetworkError("Connection failed")
            )
            mock_exchange_class.return_value = mock_exchange
            
            broker = CCXTBroker(config)
            
            with pytest.raises(Exception) as exc_info:
                await broker.execute(order)
            
            assert "Network error" in str(exc_info.value)
    
    async def test_cleanup(self, config):
        """Test broker cleanup."""
        with patch("ccxt.async_support.binance") as mock_exchange_class:
            mock_exchange = AsyncMock()
            mock_exchange.load_markets = AsyncMock()
            mock_exchange.close = AsyncMock()
            mock_exchange.closed = False
            mock_exchange_class.return_value = mock_exchange
            
            broker = CCXTBroker(config)
            await broker.initialize()
            await broker.close()
            
            mock_exchange.close.assert_called_once()
            assert broker._initialized is False