# ADR-001: Broker Adapter Pattern

**Date**: 2025-08-22  
**Status**: Accepted  
**Author**: System Architecture Team

## Context

The trading service needs to integrate with multiple cryptocurrency exchanges (Binance, Bybit, OKX, etc.) while maintaining a consistent internal interface. Each exchange has its own API format, authentication method, and behavioral quirks.

## Decision

We will implement the **Adapter Pattern** with an abstract `BaseBroker` class that defines the interface, and concrete implementations for each exchange.

## Consequences

### Positive
- Clean separation between business logic and exchange-specific code
- Easy to add new exchanges without modifying core logic
- Simplified testing with mock brokers
- Consistent error handling across exchanges

### Negative
- Additional abstraction layer adds complexity
- Potential performance overhead from translation
- Need to handle lowest common denominator features

## Implementation

```python
from abc import ABC, abstractmethod

class BaseBroker(ABC):
    @abstractmethod
    async def execute(self, order: Order) -> ExecutionResult:
        pass
    
    @abstractmethod
    async def cancel(self, order_id: str) -> bool:
        pass

class BinanceBroker(BaseBroker):
    async def execute(self, order: Order) -> ExecutionResult:
        # Binance-specific implementation
        pass

class DummyBroker(BaseBroker):
    async def execute(self, order: Order) -> ExecutionResult:
        # Test implementation
        pass
```

## Alternatives Considered

1. **Direct Integration**: Call exchange APIs directly from business logic
   - Rejected: Would create tight coupling and duplicate code

2. **Third-party Library**: Use ccxt exclusively without abstraction
   - Rejected: Less control over error handling and performance

3. **Microservice per Exchange**: Separate service for each exchange
   - Rejected: Over-engineering for current scale

## References
- [Adapter Pattern](https://refactoring.guru/design-patterns/adapter)
- [CCXT Library](https://github.com/ccxt/ccxt)