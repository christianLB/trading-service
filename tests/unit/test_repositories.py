"""Unit tests for repository classes."""
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from datetime import datetime

from pkg.domain.models import Order, Fill, Position, OrderStatus, OrderSide, OrderType
from pkg.domain.repositories import OrderRepository, FillRepository, PositionRepository


@pytest.mark.unit
@pytest.mark.asyncio
class TestOrderRepository:
    """Test OrderRepository functionality."""
    
    async def test_create_order(self):
        """Test creating a new order."""
        mock_session = AsyncMock()
        mock_session.add = MagicMock()
        mock_session.commit = AsyncMock()
        mock_session.refresh = AsyncMock()
        
        repo = OrderRepository(mock_session)
        order = Order(
            symbol="BTC/USDT",
            side=OrderSide.BUY,
            type=OrderType.MARKET,
            qty=0.01,
            client_id="test-client",
            idempotency_key="test-123"
        )
        
        result = await repo.create(order)
        
        mock_session.add.assert_called_once_with(order)
        mock_session.commit.assert_called_once()
        mock_session.refresh.assert_called_once_with(order)
        assert result == order
    
    async def test_get_order_by_id(self):
        """Test retrieving order by ID."""
        mock_session = AsyncMock()
        mock_result = AsyncMock()
        mock_result.scalars.return_value.first.return_value = Order(
            id="ord_123",
            symbol="BTC/USDT",
            side=OrderSide.BUY,
            type=OrderType.MARKET,
            qty=0.01,
            client_id="test-client"
        )
        mock_session.execute = AsyncMock(return_value=mock_result)
        
        repo = OrderRepository(mock_session)
        result = await repo.get_by_id("ord_123")
        
        assert result is not None
        assert result.id == "ord_123"
        mock_session.execute.assert_called_once()
    
    async def test_get_by_idempotency_key(self):
        """Test retrieving order by idempotency key."""
        mock_session = AsyncMock()
        mock_result = AsyncMock()
        mock_result.scalars.return_value.first.return_value = Order(
            id="ord_456",
            idempotency_key="test-key",
            symbol="BTC/USDT",
            side=OrderSide.BUY,
            type=OrderType.MARKET,
            qty=0.01,
            client_id="test-client"
        )
        mock_session.execute = AsyncMock(return_value=mock_result)
        
        repo = OrderRepository(mock_session)
        result = await repo.get_by_idempotency_key("test-key")
        
        assert result is not None
        assert result.idempotency_key == "test-key"
        mock_session.execute.assert_called_once()
    
    async def test_update_order(self):
        """Test updating an existing order."""
        mock_session = AsyncMock()
        mock_session.commit = AsyncMock()
        
        repo = OrderRepository(mock_session)
        order = Order(
            id="ord_789",
            symbol="BTC/USDT",
            side=OrderSide.BUY,
            type=OrderType.MARKET,
            qty=0.01,
            status=OrderStatus.PENDING,
            client_id="test-client"
        )
        order.status = OrderStatus.FILLED
        
        await repo.update(order)
        
        mock_session.commit.assert_called_once()


@pytest.mark.unit
@pytest.mark.asyncio  
class TestFillRepository:
    """Test FillRepository functionality."""
    
    async def test_create_fill(self):
        """Test creating a new fill."""
        mock_session = AsyncMock()
        mock_session.add = MagicMock()
        mock_session.commit = AsyncMock()
        mock_session.refresh = AsyncMock()
        
        repo = FillRepository(mock_session)
        fill = Fill(
            order_id="ord_123",
            symbol="BTC/USDT",
            side=OrderSide.BUY,
            qty=0.01,
            price=58000.0,
            client_id="test-client"
        )
        
        result = await repo.create(fill)
        
        mock_session.add.assert_called_once_with(fill)
        mock_session.commit.assert_called_once()
        mock_session.refresh.assert_called_once_with(fill)
        assert result == fill
    
    async def test_get_fills_by_order(self):
        """Test retrieving fills by order ID."""
        mock_session = AsyncMock()
        mock_result = AsyncMock()
        fills = [
            Fill(order_id="ord_123", qty=0.005, price=58000.0),
            Fill(order_id="ord_123", qty=0.005, price=58100.0)
        ]
        mock_result.scalars.return_value.all.return_value = fills
        mock_session.execute = AsyncMock(return_value=mock_result)
        
        repo = FillRepository(mock_session)
        result = await repo.get_by_order_id("ord_123")
        
        assert len(result) == 2
        assert all(f.order_id == "ord_123" for f in result)
        mock_session.execute.assert_called_once()


@pytest.mark.unit
@pytest.mark.asyncio
class TestPositionRepository:
    """Test PositionRepository functionality."""
    
    async def test_get_or_create_position(self):
        """Test getting or creating a position."""
        mock_session = AsyncMock()
        mock_result = AsyncMock()
        mock_result.scalars.return_value.first.return_value = None
        mock_session.execute = AsyncMock(return_value=mock_result)
        mock_session.add = MagicMock()
        mock_session.commit = AsyncMock()
        mock_session.refresh = AsyncMock()
        
        repo = PositionRepository(mock_session)
        result = await repo.get_or_create("BTC/USDT")
        
        assert result is not None
        assert result.symbol == "BTC/USDT"
        assert result.qty == 0
        mock_session.add.assert_called_once()
        mock_session.commit.assert_called_once()
    
    async def test_get_existing_position(self):
        """Test retrieving existing position."""
        mock_session = AsyncMock()
        mock_result = AsyncMock()
        existing_position = Position(
            symbol="BTC/USDT",
            qty=0.5,
            avg_price=58000.0,
            notional=29000.0
        )
        mock_result.scalars.return_value.first.return_value = existing_position
        mock_session.execute = AsyncMock(return_value=mock_result)
        
        repo = PositionRepository(mock_session)
        result = await repo.get_or_create("BTC/USDT")
        
        assert result == existing_position
        assert result.qty == 0.5
        mock_session.add.assert_not_called()
    
    async def test_update_position(self):
        """Test updating a position."""
        mock_session = AsyncMock()
        mock_session.commit = AsyncMock()
        
        repo = PositionRepository(mock_session)
        position = Position(
            symbol="BTC/USDT",
            qty=0.5,
            avg_price=58000.0,
            notional=29000.0
        )
        position.qty = 1.0
        position.notional = 58000.0
        
        await repo.update(position)
        
        mock_session.commit.assert_called_once()
    
    async def test_get_total_notional(self):
        """Test calculating total notional across all positions."""
        mock_session = AsyncMock()
        mock_result = AsyncMock()
        mock_result.scalar.return_value = 150000.0
        mock_session.execute = AsyncMock(return_value=mock_result)
        
        repo = PositionRepository(mock_session)
        result = await repo.get_total_notional()
        
        assert result == 150000.0
        mock_session.execute.assert_called_once()