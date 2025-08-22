# 🧪 Testing Strategy

> **Purpose**: Define comprehensive testing approach, standards, and requirements for the Trading Service.

## Testing Philosophy

We follow the **Testing Pyramid** approach with emphasis on:
- Fast, reliable unit tests as the foundation
- Integration tests for critical paths
- End-to-end tests for user scenarios
- Performance tests for SLA compliance

```
         /\
        /E2E\        <- Few, expensive, slow
       /------\
      /Integration\  <- Moderate coverage
     /-------------\
    /   Unit Tests  \ <- Many, fast, cheap
   /-----------------\
```

## Test Organization

```
tests/
├── unit/                    # Fast, isolated tests
│   ├── test_risk_engine.py
│   ├── test_brokers.py
│   ├── test_domain.py
│   └── test_utils.py
├── integration/             # Component integration
│   ├── test_api_flow.py
│   ├── test_database.py
│   ├── test_redis.py
│   └── test_webhooks.py
├── e2e/                    # End-to-end scenarios
│   ├── test_order_lifecycle.py
│   ├── test_risk_scenarios.py
│   └── test_production_flow.py
├── performance/            # Load & stress tests
│   ├── test_load.py
│   ├── test_stress.py
│   └── test_latency.py
├── fixtures/               # Shared test data
│   ├── orders.json
│   ├── positions.json
│   └── market_data.json
└── conftest.py            # Pytest configuration
```

## Coverage Requirements

### Minimum Coverage by Component

| Component | Unit | Integration | E2E | Total |
|-----------|------|-------------|-----|-------|
| Risk Engine | 95% | 90% | 80% | **92%** |
| Brokers | 90% | 85% | 70% | **85%** |
| API Endpoints | 85% | 90% | 80% | **87%** |
| Domain Models | 95% | - | - | **95%** |
| Utilities | 90% | - | - | **90%** |
| **Overall** | **90%** | **85%** | **75%** | **85%** |

### Critical Path Coverage

These paths MUST have 100% test coverage:
- Order creation and validation
- Risk limit checks
- Position calculations
- Order execution flow
- Error handling and recovery

## Test Types

### Unit Tests

**Purpose**: Test individual functions and classes in isolation

**Characteristics**:
- No external dependencies (database, network, files)
- Use mocks and stubs for dependencies
- Execute in < 100ms per test
- Run on every commit

**Example**:
```python
# tests/unit/test_risk_engine.py
@pytest.mark.unit
async def test_position_limit_check():
    """Test that position limits are enforced correctly."""
    engine = RiskEngine()
    order = create_test_order(qty=1000, price=50000)
    
    with patch('pkg.domain.repositories.PositionRepository') as mock_repo:
        mock_repo.get_total_notional.return_value = 4000
        
        allowed, reason = await engine.check_order(order, mock_session)
        
        assert not allowed
        assert "Position limit exceeded" in reason
```

### Integration Tests

**Purpose**: Test interaction between components

**Characteristics**:
- May use test database
- Test API contracts
- Verify data flow
- Execute in < 1s per test

**Example**:
```python
# tests/integration/test_api_flow.py
@pytest.mark.integration
async def test_order_creation_flow(test_client, test_db):
    """Test complete order creation through API."""
    response = await test_client.post(
        "/orders",
        json={
            "symbol": "BTC/USDT",
            "side": "buy",
            "type": "market",
            "qty": 0.01
        },
        headers={"Authorization": f"Bearer {TEST_TOKEN}"}
    )
    
    assert response.status_code == 200
    assert "orderId" in response.json()
    
    # Verify in database
    order = await test_db.get_order(response.json()["orderId"])
    assert order is not None
```

### End-to-End Tests

**Purpose**: Test complete user scenarios

**Characteristics**:
- Use real services (or test versions)
- Test full workflows
- Verify business requirements
- Execute in < 10s per test

**Example**:
```python
# tests/e2e/test_order_lifecycle.py
@pytest.mark.e2e
async def test_complete_trading_session():
    """Test a complete trading session from login to position close."""
    # Create order
    order = await create_market_order("BTC/USDT", "buy", 0.1)
    assert order.status == "filled"
    
    # Check position
    position = await get_position("BTC/USDT")
    assert position.qty == 0.1
    
    # Close position
    close_order = await create_market_order("BTC/USDT", "sell", 0.1)
    assert close_order.status == "filled"
    
    # Verify flat
    final_position = await get_position("BTC/USDT")
    assert final_position.qty == 0
```

### Performance Tests

**Purpose**: Ensure system meets performance requirements

**Characteristics**:
- Test under load
- Measure latency
- Verify throughput
- Check resource usage

**Example**:
```python
# tests/performance/test_load.py
@pytest.mark.performance
async def test_order_throughput():
    """Test system can handle 100 orders per second."""
    start_time = time.time()
    tasks = []
    
    for _ in range(100):
        tasks.append(create_order_async())
    
    results = await asyncio.gather(*tasks)
    duration = time.time() - start_time
    
    assert duration < 1.0  # 100 orders in < 1 second
    assert all(r.status_code == 200 for r in results)
```

## Test Execution

### Local Development

```bash
# Run all tests
pytest

# Run with coverage
pytest --cov=apps --cov=pkg --cov-report=html

# Run specific test type
pytest -m unit
pytest -m integration
pytest -m e2e

# Run specific file
pytest tests/unit/test_risk_engine.py

# Run with verbose output
pytest -v

# Run failed tests only
pytest --lf

# Run tests in parallel
pytest -n auto
```

### CI/CD Pipeline

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - name: Run unit tests
        run: pytest -m unit --cov

  integration-tests:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
      redis:
        image: redis:7
    steps:
      - name: Run integration tests
        run: pytest -m integration

  e2e-tests:
    runs-on: ubuntu-latest
    steps:
      - name: Run E2E tests
        run: pytest -m e2e
```

## Test Data Management

### Fixtures

```python
# tests/conftest.py
@pytest.fixture
async def test_order():
    """Provide a test order."""
    return Order(
        symbol="BTC/USDT",
        side="buy",
        type="market",
        qty=0.01,
        client_id="test-client"
    )

@pytest.fixture
async def test_db():
    """Provide a test database session."""
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    
    async with AsyncSession(test_engine) as session:
        yield session
        await session.rollback()
```

### Test Data Files

```json
// tests/fixtures/orders.json
{
  "valid_market_order": {
    "symbol": "BTC/USDT",
    "side": "buy",
    "type": "market",
    "qty": 0.01,
    "clientId": "test-001",
    "idempotencyKey": "unique-001"
  },
  "invalid_symbol_order": {
    "symbol": "INVALID/PAIR",
    "side": "buy",
    "type": "market",
    "qty": 0.01
  }
}
```

## Mocking Strategy

### External Services

```python
# Always mock external services in unit tests
@patch('ccxt.binance')
def test_exchange_integration(mock_exchange):
    mock_exchange.create_order.return_value = {
        'id': '12345',
        'status': 'closed',
        'filled': 0.01
    }
```

### Time-based Tests

```python
# Use freezegun for time-dependent tests
from freezegun import freeze_time

@freeze_time("2025-08-22 12:00:00")
def test_daily_loss_calculation():
    # Test will always run at the same time
    pass
```

## Test Best Practices

### Do's ✅

1. **Write tests first** (TDD when possible)
2. **Keep tests simple** and focused
3. **Use descriptive names** that explain what's being tested
4. **Test one thing** per test
5. **Use fixtures** for common setup
6. **Mock external dependencies** in unit tests
7. **Test edge cases** and error conditions
8. **Keep tests fast** (< 10s for entire unit suite)
9. **Use property-based testing** for complex logic
10. **Clean up** after tests (database, files, etc.)

### Don'ts ❌

1. **Don't test implementation details** - test behavior
2. **Don't use production data** in tests
3. **Don't skip failing tests** - fix or delete them
4. **Don't rely on test order** - tests should be independent
5. **Don't use sleep()** - use proper synchronization
6. **Don't hardcode values** - use constants or fixtures
7. **Don't test external libraries** - trust they work
8. **Don't ignore flaky tests** - fix the root cause

## Test Metrics

### Key Metrics to Track

| Metric | Target | Current | Trend |
|--------|--------|---------|-------|
| Code Coverage | 85% | 72% | ↗️ |
| Test Execution Time | < 60s | 45s | ✅ |
| Test Flakiness | < 1% | 2% | ↘️ |
| Tests per Feature | > 5 | 4.2 | ↗️ |
| Bug Escape Rate | < 5% | 8% | ↘️ |

### Coverage Reports

```bash
# Generate HTML coverage report
pytest --cov=apps --cov=pkg --cov-report=html

# View report
open htmlcov/index.html

# Generate terminal report
pytest --cov=apps --cov=pkg --cov-report=term-missing
```

## Continuous Testing

### Pre-commit Hooks

```yaml
# .pre-commit-config.yaml
- repo: local
  hooks:
    - id: pytest-check
      name: pytest-check
      entry: pytest -m "unit" --tb=short
      language: system
      pass_filenames: false
      always_run: true
```

### Watch Mode

```bash
# Auto-run tests on file changes
ptw -- -m unit  # pytest-watch

# Or use nodemon
nodemon --exec "pytest -m unit" --ext py
```

## Testing Tools

### Required Tools

| Tool | Purpose | Installation |
|------|---------|--------------|
| pytest | Test framework | `pip install pytest` |
| pytest-asyncio | Async test support | `pip install pytest-asyncio` |
| pytest-cov | Coverage reporting | `pip install pytest-cov` |
| pytest-mock | Mocking utilities | `pip install pytest-mock` |
| faker | Test data generation | `pip install faker` |
| freezegun | Time mocking | `pip install freezegun` |
| httpx | API testing | `pip install httpx` |

### Optional Tools

| Tool | Purpose | Installation |
|------|---------|--------------|
| pytest-xdist | Parallel execution | `pip install pytest-xdist` |
| pytest-benchmark | Performance testing | `pip install pytest-benchmark` |
| hypothesis | Property testing | `pip install hypothesis` |
| locust | Load testing | `pip install locust` |

## Troubleshooting

### Common Issues

#### Tests Failing in CI but Pass Locally
- Check environment variables
- Verify database state
- Check timezone differences
- Review service dependencies

#### Flaky Tests
- Add proper waits/retries
- Mock time-dependent code
- Ensure test isolation
- Check for race conditions

#### Slow Tests
- Use pytest-xdist for parallel execution
- Mock expensive operations
- Use smaller datasets
- Profile with pytest-benchmark

## References

- [Pytest Documentation](https://docs.pytest.org/)
- [Testing Best Practices](https://testdriven.io/blog/testing-best-practices/)
- [Python Testing 101](https://realpython.com/python-testing/)
- [Test Pyramid](https://martinfowler.com/bliki/TestPyramid.html)