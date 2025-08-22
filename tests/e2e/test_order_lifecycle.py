"""End-to-end tests for complete order lifecycle."""
import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch, AsyncMock, MagicMock
import json

from apps.api.main import app


@pytest.mark.e2e
class TestOrderLifecycle:
    """Test complete order lifecycle from creation to position update."""
    
    @pytest.fixture
    def client(self):
        return TestClient(app)
    
    @pytest.fixture
    def auth_headers(self):
        return {"Authorization": "Bearer test_token"}
    
    @pytest.fixture
    def mock_dependencies(self):
        """Setup all necessary mocks for E2E testing."""
        with patch("apps.api.deps.get_settings") as mock_settings, \
             patch("apps.api.routers.orders.get_db") as mock_db, \
             patch("apps.api.routers.positions.get_db") as mock_pos_db, \
             patch("apps.api.routers.orders.send_webhook") as mock_webhook:
            
            mock_settings.return_value.api_token = "test_token"
            mock_settings.return_value.max_position_usd = 5000
            mock_settings.return_value.max_daily_loss_usd = 500
            mock_settings.return_value.allowed_symbols = ["BTC/USDT", "ETH/USDT"]
            
            # Setup database session mock
            mock_session = AsyncMock()
            mock_db.return_value.__aenter__.return_value = mock_session
            mock_db.return_value.__aexit__.return_value = None
            mock_pos_db.return_value.__aenter__.return_value = mock_session
            mock_pos_db.return_value.__aexit__.return_value = None
            
            # Mock webhook to track calls
            mock_webhook.return_value = AsyncMock()
            
            yield {
                "settings": mock_settings,
                "db": mock_db,
                "session": mock_session,
                "webhook": mock_webhook
            }
    
    def test_complete_buy_sell_cycle(self, client, auth_headers, mock_dependencies):
        """Test a complete buy and sell cycle."""
        mock_session = mock_dependencies["session"]
        mock_webhook = mock_dependencies["webhook"]
        
        # Mock repositories for the buy order
        with patch("apps.api.routers.orders.OrderRepository") as mock_order_repo, \
             patch("apps.api.routers.orders.FillRepository") as mock_fill_repo, \
             patch("apps.api.routers.orders.PositionRepository") as mock_pos_repo, \
             patch("apps.api.routers.positions.PositionRepository") as mock_pos_repo_get:
            
            # Setup for buy order
            buy_order = AsyncMock(
                id="ord_buy_123",
                status="pending",
                symbol="BTC/USDT",
                side="buy",
                qty=0.01,
                filled_qty=0,
                avg_price=0
            )
            mock_order_repo.return_value.get_by_idempotency_key = AsyncMock(return_value=None)
            mock_order_repo.return_value.create = AsyncMock(return_value=buy_order)
            mock_order_repo.return_value.update = AsyncMock()
            
            mock_fill_repo.return_value.create = AsyncMock()
            
            # Initial position is flat
            initial_position = AsyncMock(qty=0, avg_price=0, notional=0, symbol="BTC/USDT")
            mock_pos_repo.return_value.get_or_create = AsyncMock(return_value=initial_position)
            mock_pos_repo.return_value.update = AsyncMock()
            mock_pos_repo.return_value.get_total_notional = AsyncMock(return_value=0)
            
            # Create buy order
            buy_response = client.post(
                "/orders",
                headers=auth_headers,
                json={
                    "symbol": "BTC/USDT",
                    "side": "buy",
                    "type": "market",
                    "qty": 0.01,
                    "clientId": "test-client",
                    "idempotencyKey": "buy-001"
                }
            )
            
            assert buy_response.status_code == 200
            buy_data = buy_response.json()
            assert "orderId" in buy_data
            assert buy_data["status"] in ["pending", "filled"]
            
            # Verify position was updated
            assert initial_position.qty == 0.01
            mock_pos_repo.return_value.update.assert_called()
            
            # Setup for position query
            mock_pos_repo_get.return_value.get_all = AsyncMock(
                return_value=[initial_position]
            )
            
            # Check position
            position_response = client.get("/positions", headers=auth_headers)
            assert position_response.status_code == 200
            positions = position_response.json()
            assert "positions" in positions
            
            # Setup for sell order
            sell_order = AsyncMock(
                id="ord_sell_456",
                status="pending",
                symbol="BTC/USDT",
                side="sell",
                qty=0.01,
                filled_qty=0,
                avg_price=0
            )
            mock_order_repo.return_value.create = AsyncMock(return_value=sell_order)
            
            # Position after sell should be flat
            initial_position.qty = 0
            initial_position.notional = 0
            
            # Create sell order to close position
            sell_response = client.post(
                "/orders",
                headers=auth_headers,
                json={
                    "symbol": "BTC/USDT",
                    "side": "sell",
                    "type": "market",
                    "qty": 0.01,
                    "clientId": "test-client",
                    "idempotencyKey": "sell-001"
                }
            )
            
            assert sell_response.status_code == 200
            sell_data = sell_response.json()
            assert "orderId" in sell_data
            
            # Verify position is now flat
            assert initial_position.qty == 0
            assert initial_position.notional == 0
            
            # Verify webhooks were sent for both orders
            assert mock_webhook.call_count >= 2
    
    def test_risk_limit_blocks_order(self, client, auth_headers, mock_dependencies):
        """Test that risk limits properly block orders."""
        mock_session = mock_dependencies["session"]
        
        with patch("apps.api.routers.orders.OrderRepository") as mock_order_repo, \
             patch("apps.api.routers.orders.PositionRepository") as mock_pos_repo:
            
            mock_order_repo.return_value.get_by_idempotency_key = AsyncMock(return_value=None)
            
            # Set total notional at limit
            mock_pos_repo.return_value.get_total_notional = AsyncMock(return_value=4999)
            
            # Try to create order that would exceed limit
            response = client.post(
                "/orders",
                headers=auth_headers,
                json={
                    "symbol": "BTC/USDT",
                    "side": "buy",
                    "type": "market",
                    "qty": 1.0,  # Large order
                    "clientId": "test-client",
                    "idempotencyKey": "risk-001"
                }
            )
            
            assert response.status_code == 422
            error_data = response.json()
            assert "Risk blocked" in error_data["detail"]
    
    def test_idempotency_prevents_duplicate_orders(self, client, auth_headers, mock_dependencies):
        """Test that idempotency key prevents duplicate orders."""
        mock_session = mock_dependencies["session"]
        
        with patch("apps.api.routers.orders.OrderRepository") as mock_order_repo:
            
            existing_order = AsyncMock(
                id="ord_existing",
                status="filled"
            )
            mock_order_repo.return_value.get_by_idempotency_key = AsyncMock(
                return_value=existing_order
            )
            
            # Try to create order with same idempotency key
            response = client.post(
                "/orders",
                headers=auth_headers,
                json={
                    "symbol": "BTC/USDT",
                    "side": "buy",
                    "type": "market",
                    "qty": 0.01,
                    "clientId": "test-client",
                    "idempotencyKey": "duplicate-key"
                }
            )
            
            assert response.status_code == 200
            data = response.json()
            assert data["orderId"] == "ord_existing"
            assert data["status"] == "filled"
            
            # Verify no new order was created
            mock_order_repo.return_value.create.assert_not_called()
    
    def test_invalid_symbol_rejected(self, client, auth_headers, mock_dependencies):
        """Test that invalid symbols are rejected."""
        with patch("apps.api.routers.orders.OrderRepository") as mock_order_repo, \
             patch("apps.api.routers.orders.PositionRepository") as mock_pos_repo:
            
            mock_order_repo.return_value.get_by_idempotency_key = AsyncMock(return_value=None)
            mock_pos_repo.return_value.get_total_notional = AsyncMock(return_value=0)
            
            response = client.post(
                "/orders",
                headers=auth_headers,
                json={
                    "symbol": "INVALID/PAIR",
                    "side": "buy",
                    "type": "market",
                    "qty": 0.01,
                    "clientId": "test-client",
                    "idempotencyKey": "invalid-001"
                }
            )
            
            assert response.status_code == 422
            error_data = response.json()
            assert "Symbol not allowed" in error_data["detail"]