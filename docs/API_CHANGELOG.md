# 📝 API Changelog

> **Purpose**: Track all API changes, deprecations, and version history.

All notable changes to the Trading Service API will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- WebSocket endpoints for real-time updates
- Batch order creation endpoint
- Historical data endpoints
- Strategy management endpoints

## [0.2.0] - 2025-09-15 (Planned)

### Added
- Webhook signature validation using HMAC-SHA256
- Rate limiting per API token
- Request correlation IDs in headers
- Bulk position close endpoint

### Changed
- Order response now includes `estimatedFees` field
- Position endpoint returns `unrealizedPnl` field
- Increased default rate limit to 100 requests/minute

### Fixed
- Position calculation accuracy for partial fills
- Timezone handling in timestamp fields

## [0.1.0] - 2025-08-22

### Added

#### Endpoints
- `GET /healthz` - Health check endpoint
  ```json
  Response: {
    "status": "healthy",
    "timestamp": "2025-08-22T12:00:00Z",
    "database": "healthy",
    "redis": "healthy"
  }
  ```

- `POST /orders` - Create new order
  ```json
  Request: {
    "symbol": "BTC/USDT",
    "side": "buy|sell",
    "type": "market|limit",
    "qty": 0.01,
    "limitPrice": 50000,
    "clientId": "client-001",
    "idempotencyKey": "unique-key"
  }
  
  Response: {
    "orderId": "ord_abc123",
    "status": "accepted|filled|rejected"
  }
  ```

- `GET /orders/{orderId}` - Get order details
  ```json
  Response: {
    "orderId": "ord_abc123",
    "symbol": "BTC/USDT",
    "side": "buy",
    "type": "market",
    "qty": 0.01,
    "limitPrice": null,
    "filledQty": 0.01,
    "avgPrice": 50000,
    "status": "filled",
    "clientId": "client-001",
    "createdAt": "2025-08-22T12:00:00Z",
    "updatedAt": "2025-08-22T12:00:01Z"
  }
  ```

- `GET /positions` - List current positions
  ```json
  Response: [{
    "symbol": "BTC/USDT",
    "qty": 0.01,
    "avgPrice": 50000,
    "notional": 500,
    "pnl": 10.50,
    "updatedAt": "2025-08-22T12:00:00Z"
  }]
  ```

- `GET /metrics` - Prometheus metrics
  ```
  # HELP orders_total Total number of orders created
  # TYPE orders_total counter
  orders_total 42
  
  # HELP fills_total Total number of order fills
  # TYPE fills_total counter
  fills_total 38
  
  # HELP risk_blocks_total Total number of risk blocks
  # TYPE risk_blocks_total counter
  risk_blocks_total 4
  ```

#### Authentication
- Bearer token authentication via `Authorization` header
- Token validation on all endpoints except `/healthz` and `/metrics`

#### Risk Limits
- `MAX_POS_USD`: Maximum position size in USD
- `MAX_DAILY_LOSS_USD`: Maximum daily loss allowed
- Symbol whitelist validation

#### Error Responses
```json
// 400 Bad Request
{
  "detail": "Invalid order parameters"
}

// 401 Unauthorized
{
  "detail": "Invalid authentication token"
}

// 422 Unprocessable Entity
{
  "detail": "Risk limit exceeded: Position limit 5000 USD"
}

// 500 Internal Server Error
{
  "detail": "Internal server error"
}
```

## API Versioning Strategy

### Version Format
- Format: `vMAJOR.MINOR.PATCH`
- Example: `v1.2.3`

### Versioning Rules

#### Major Version (Breaking Changes)
- Removing endpoints
- Changing required fields
- Modifying response structure
- Changing authentication method

#### Minor Version (Backwards Compatible)
- Adding new endpoints
- Adding optional fields
- Adding new response fields
- Performance improvements

#### Patch Version (Bug Fixes)
- Bug fixes
- Security patches
- Documentation updates

### Deprecation Policy

1. **Announcement**: Minimum 3 months notice
2. **Migration Guide**: Provided with deprecation notice
3. **Sunset Period**: 6 months after new version
4. **Headers**: `X-API-Deprecated: true` and `X-API-Sunset-Date: 2025-12-31`

## Migration Guides

### Migrating from 0.1.0 to 0.2.0

#### 1. Webhook Signature Validation

**Before (0.1.0):**
```python
# No signature validation
webhook_url = "https://example.com/webhook"
requests.post(webhook_url, json=payload)
```

**After (0.2.0):**
```python
# HMAC signature required
import hmac
import hashlib

signature = hmac.new(
    WEBHOOK_SECRET.encode(),
    body.encode(),
    hashlib.sha256
).hexdigest()

headers = {"X-Signature": signature}
requests.post(webhook_url, json=payload, headers=headers)
```

#### 2. New Response Fields

**Position Response Enhancement:**
```json
// Added field
{
  "symbol": "BTC/USDT",
  "qty": 0.01,
  "avgPrice": 50000,
  "notional": 500,
  "pnl": 10.50,
  "unrealizedPnl": 5.25,  // NEW
  "updatedAt": "2025-08-22T12:00:00Z"
}
```

## Rate Limiting

### Current Limits

| Endpoint | Rate Limit | Window |
|----------|-----------|--------|
| `/orders` POST | 10 req | 1 minute |
| `/orders` GET | 100 req | 1 minute |
| `/positions` GET | 100 req | 1 minute |
| `/healthz` GET | No limit | - |
| `/metrics` GET | No limit | - |

### Rate Limit Headers

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1692705600
```

### Rate Limit Response

```json
// 429 Too Many Requests
{
  "detail": "Rate limit exceeded",
  "retry_after": 30
}
```

## WebSocket API (Coming Soon)

### Planned Channels

```javascript
// Order Updates
ws://localhost:8085/ws/orders
{
  "action": "subscribe",
  "channel": "orders",
  "auth": "Bearer token"
}

// Position Updates
ws://localhost:8085/ws/positions
{
  "action": "subscribe",
  "channel": "positions",
  "symbols": ["BTC/USDT", "ETH/USDT"]
}

// Market Data
ws://localhost:8085/ws/market
{
  "action": "subscribe",
  "channel": "market",
  "symbols": ["BTC/USDT"],
  "depth": 10
}
```

## SDK Support

### Official SDKs (Planned)

| Language | Package | Status |
|----------|---------|--------|
| Python | `trading-service-sdk` | 🔵 Planned |
| JavaScript | `@trading/service-sdk` | 🔵 Planned |
| Go | `github.com/trading/sdk-go` | 🔵 Planned |

### Example Usage (Python)

```python
from trading_service import TradingClient

client = TradingClient(
    base_url="http://192.168.1.11:8085",
    api_token="your-token"
)

# Create order
order = client.create_order(
    symbol="BTC/USDT",
    side="buy",
    type="market",
    qty=0.01
)

# Get positions
positions = client.get_positions()
```

## OpenAPI Specification

The complete OpenAPI specification is available at:
- Development: http://localhost:8085/docs
- Production: http://192.168.1.11:8085/docs
- Raw spec: `/openapi.json`

## Breaking Changes Log

### Future Breaking Changes (v1.0.0)

⚠️ **Planned for 2025-10-31**

1. **Order ID Format Change**
   - Current: `ord_abc123`
   - Future: UUID format `550e8400-e29b-41d4-a716-446655440000`

2. **Timestamp Format**
   - Current: ISO 8601 string
   - Future: Unix timestamp (milliseconds)

3. **Error Response Structure**
   - Current: `{"detail": "error message"}`
   - Future: `{"error": {"code": "ERR001", "message": "error message"}}`

## Support

- **Documentation**: [API Docs](http://192.168.1.11:8085/docs)
- **Issues**: [GitHub Issues](https://github.com/christianLB/trading-service/issues)
- **Status Page**: [System Status](#) (Coming soon)

---

*For implementation details, see [contracts/openapi.yaml](../contracts/openapi.yaml)*