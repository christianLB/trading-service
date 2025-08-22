"""Integration tests for webhook functionality."""
import json
import hmac
import hashlib
from unittest.mock import patch, AsyncMock
import pytest
import httpx

from pkg.infra.webhooks import send_webhook
from pkg.infra.settings import Settings


@pytest.mark.integration
class TestWebhookFlow:
    """Test webhook integration flow."""
    
    @pytest.mark.asyncio
    async def test_send_webhook_with_signature(self):
        """Test sending webhook with proper HMAC signature."""
        settings = Settings(
            webhook_url="http://test.example.com/webhook",
            webhook_secret="test_secret"
        )
        
        with patch("pkg.infra.webhooks.get_settings", return_value=settings), \
             patch("httpx.AsyncClient.post") as mock_post:
            
            mock_response = AsyncMock()
            mock_response.is_error = False
            mock_response.status_code = 200
            mock_post.return_value = mock_response
            
            await send_webhook("order_filled", {
                "orderId": "ord_123",
                "symbol": "BTC/USDT",
                "filledQty": 0.01,
                "avgPrice": 58000.0
            })
            
            # Verify the call was made
            mock_post.assert_called_once()
            call_args = mock_post.call_args
            
            # Verify URL
            assert call_args[0][0] == "http://test.example.com/webhook"
            
            # Verify headers
            headers = call_args[1]["headers"]
            assert "X-Signature" in headers
            assert headers["Content-Type"] == "application/json"
            
            # Verify signature
            body = call_args[1]["content"]
            expected_signature = hmac.new(
                b"test_secret",
                body.encode() if isinstance(body, str) else body,
                hashlib.sha256
            ).hexdigest()
            assert headers["X-Signature"] == expected_signature
    
    @pytest.mark.asyncio
    async def test_webhook_includes_timestamp(self):
        """Test that webhook payload includes timestamp."""
        settings = Settings(
            webhook_url="http://test.example.com/webhook",
            webhook_secret="test_secret"
        )
        
        with patch("pkg.infra.webhooks.get_settings", return_value=settings), \
             patch("httpx.AsyncClient.post") as mock_post:
            
            mock_response = AsyncMock()
            mock_response.is_error = False
            mock_response.status_code = 200
            mock_post.return_value = mock_response
            
            await send_webhook("test_event", {"data": "test"})
            
            call_args = mock_post.call_args
            body = json.loads(call_args[1]["content"])
            
            assert "ts" in body
            assert "event" in body
            assert body["event"] == "test_event"
            assert body["data"] == "test"
    
    @pytest.mark.asyncio
    async def test_webhook_handles_no_url(self):
        """Test webhook behavior when URL is not configured."""
        settings = Settings(webhook_url=None)
        
        with patch("pkg.infra.webhooks.get_settings", return_value=settings), \
             patch("httpx.AsyncClient.post") as mock_post, \
             patch("pkg.infra.webhooks.logger") as mock_logger:
            
            await send_webhook("test_event", {"data": "test"})
            
            # Should not attempt to send
            mock_post.assert_not_called()
            
            # Should log debug message
            mock_logger.debug.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_webhook_handles_error_response(self):
        """Test webhook behavior on error response."""
        settings = Settings(
            webhook_url="http://test.example.com/webhook",
            webhook_secret="test_secret"
        )
        
        with patch("pkg.infra.webhooks.get_settings", return_value=settings), \
             patch("httpx.AsyncClient.post") as mock_post, \
             patch("pkg.infra.webhooks.logger") as mock_logger:
            
            mock_response = AsyncMock()
            mock_response.is_error = True
            mock_response.status_code = 500
            mock_response.text = "Internal Server Error"
            mock_post.return_value = mock_response
            
            await send_webhook("test_event", {"data": "test"})
            
            # Should log warning
            mock_logger.warning.assert_called_once()
            call_args = mock_logger.warning.call_args
            assert "Webhook failed" in call_args[0][0]
    
    @pytest.mark.asyncio
    async def test_webhook_handles_network_error(self):
        """Test webhook behavior on network error."""
        settings = Settings(
            webhook_url="http://test.example.com/webhook",
            webhook_secret="test_secret"
        )
        
        with patch("pkg.infra.webhooks.get_settings", return_value=settings), \
             patch("httpx.AsyncClient.post") as mock_post, \
             patch("pkg.infra.webhooks.logger") as mock_logger:
            
            mock_post.side_effect = httpx.ConnectError("Connection failed")
            
            await send_webhook("test_event", {"data": "test"})
            
            # Should log error
            mock_logger.error.assert_called_once()
            call_args = mock_logger.error.call_args
            assert "Webhook error" in call_args[0][0]
    
    @pytest.mark.asyncio
    async def test_webhook_timeout(self):
        """Test webhook timeout handling."""
        settings = Settings(
            webhook_url="http://test.example.com/webhook",
            webhook_secret="test_secret"
        )
        
        with patch("pkg.infra.webhooks.get_settings", return_value=settings), \
             patch("httpx.AsyncClient.post") as mock_post, \
             patch("pkg.infra.webhooks.logger") as mock_logger:
            
            mock_post.side_effect = httpx.TimeoutException("Request timeout")
            
            await send_webhook("test_event", {"data": "test"})
            
            # Should log error
            mock_logger.error.assert_called_once()
            
            # Verify timeout was set
            call_args = mock_post.call_args
            assert call_args[1]["timeout"] == 5.0
    
    @pytest.mark.asyncio
    async def test_order_filled_webhook_format(self):
        """Test the specific format of order_filled webhook."""
        settings = Settings(
            webhook_url="http://test.example.com/webhook",
            webhook_secret="test_secret"
        )
        
        with patch("pkg.infra.webhooks.get_settings", return_value=settings), \
             patch("httpx.AsyncClient.post") as mock_post:
            
            mock_response = AsyncMock()
            mock_response.is_error = False
            mock_response.status_code = 200
            mock_post.return_value = mock_response
            
            await send_webhook("order_filled", {
                "orderId": "ord_abc123",
                "symbol": "ETH/USDT",
                "filledQty": 2.5,
                "avgPrice": 3000.0
            })
            
            call_args = mock_post.call_args
            body = json.loads(call_args[1]["content"])
            
            # Verify order_filled specific fields
            assert body["event"] == "order_filled"
            assert body["orderId"] == "ord_abc123"
            assert body["symbol"] == "ETH/USDT"
            assert body["filledQty"] == 2.5
            assert body["avgPrice"] == 3000.0
            assert "ts" in body