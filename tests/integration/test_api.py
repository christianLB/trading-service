import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch, AsyncMock

from apps.api.main import app


@pytest.fixture
def client():
    return TestClient(app)


def test_health_endpoint(client):
    with patch("apps.api.routers.health.get_db_session") as mock_db, \
         patch("apps.api.routers.health.get_redis_client") as mock_redis:
        
        mock_db.return_value.__aenter__.return_value.execute = AsyncMock(
            return_value=AsyncMock(scalar=lambda: 1)
        )
        mock_redis.return_value.ping = AsyncMock()
        
        response = client.get("/healthz")
        
        assert response.status_code == 200
        data = response.json()
        assert data["status"] in ["healthy", "degraded"]
        assert "timestamp" in data
        assert "database" in data
        assert "redis" in data


def test_orders_endpoint_requires_auth(client):
    response = client.post(
        "/orders",
        json={
            "symbol": "BTC/USDT",
            "side": "buy",
            "type": "market",
            "qty": 0.01,
            "clientId": "test",
            "idempotencyKey": "test-123",
        }
    )
    
    assert response.status_code == 403


def test_orders_endpoint_with_auth(client):
    with patch("apps.api.deps.get_settings") as mock_settings, \
         patch("apps.api.routers.orders.get_db") as mock_db, \
         patch("apps.api.routers.orders.RiskEngine") as mock_risk, \
         patch("apps.api.routers.orders.DummyBroker") as mock_broker, \
         patch("apps.api.routers.orders.OrderRepository") as mock_repo, \
         patch("apps.api.routers.orders.FillRepository") as mock_fill_repo, \
         patch("apps.api.routers.orders.PositionRepository") as mock_pos_repo, \
         patch("apps.api.routers.orders.send_webhook") as mock_webhook:
        
        mock_settings.return_value.api_token = "test_token"
        mock_risk.return_value.check_order = AsyncMock(return_value=(True, "OK"))
        mock_broker.return_value.execute = AsyncMock(
            return_value=AsyncMock(qty=0.01, avg_price=58000.0)
        )
        mock_repo.return_value.get_by_idempotency_key = AsyncMock(return_value=None)
        mock_repo.return_value.create = AsyncMock(
            return_value=AsyncMock(id="ord_test123", status="pending", filled_qty=0, avg_price=0)
        )
        mock_repo.return_value.update = AsyncMock()
        
        # Mock fill repository
        mock_fill_repo.return_value.create = AsyncMock()
        
        # Mock position repository
        mock_position = AsyncMock(qty=0, avg_price=0, notional=0)
        mock_pos_repo.return_value.get_or_create = AsyncMock(return_value=mock_position)
        mock_pos_repo.return_value.update = AsyncMock()
        
        # Mock webhook
        mock_webhook.return_value = AsyncMock()
        
        response = client.post(
            "/orders",
            headers={"Authorization": "Bearer test_token"},
            json={
                "symbol": "BTC/USDT",
                "side": "buy",
                "type": "market",
                "qty": 0.01,
                "clientId": "test",
                "idempotencyKey": "test-123",
            }
        )
        
        assert response.status_code == 200
        data = response.json()
        assert "orderId" in data
        assert data["status"] in ["accepted", "pending", "filled"]


def test_metrics_endpoint(client):
    response = client.get("/metrics")
    
    assert response.status_code == 200
    assert response.headers["content-type"] == "text/plain; charset=utf-8"
    assert "orders_total" in response.text
    assert "fills_total" in response.text
    assert "risk_blocks_total" in response.text