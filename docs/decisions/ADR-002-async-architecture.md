# ADR-002: Async-First Architecture

**Date**: 2025-08-22  
**Status**: Accepted  
**Author**: System Architecture Team

## Context

Trading systems require high throughput and low latency while handling I/O-intensive operations like database queries, exchange API calls, and webhook notifications. Python's Global Interpreter Lock (GIL) makes threading less effective for CPU-bound tasks.

## Decision

We will use **async/await** patterns throughout the application with FastAPI and asyncio, making all I/O operations non-blocking.

## Consequences

### Positive
- Better resource utilization with concurrent I/O operations
- Lower memory footprint compared to threading
- Natural fit with FastAPI's async support
- Improved scalability for handling many simultaneous connections

### Negative
- Requires async-compatible libraries (asyncpg, aioredis, httpx)
- More complex debugging and error handling
- Team needs to understand async programming patterns
- Risk of blocking the event loop with CPU-intensive operations

## Implementation

```python
# Good: Async all the way down
async def create_order(order: OrderRequest) -> OrderResponse:
    async with get_db_session() as session:
        # Async database operation
        risk_check = await risk_engine.check_order(order, session)
        
        if risk_check.allowed:
            # Async broker call
            result = await broker.execute(order)
            
            # Async save to database
            await session.commit()
            
            # Async webhook notification
            await notify_webhook(result)
            
        return OrderResponse(...)

# Bad: Mixing sync and async
async def bad_example():
    time.sleep(1)  # Blocks event loop!
    requests.get(url)  # Use httpx instead!
```

## Guidelines

1. Use `async def` for all route handlers
2. Use async libraries (httpx, asyncpg, aioredis)
3. Never use blocking operations in async functions
4. Use `asyncio.create_task()` for fire-and-forget operations
5. Use `asyncio.gather()` for parallel operations

## Alternatives Considered

1. **Synchronous with Threading**: Traditional thread pool for concurrency
   - Rejected: Higher memory usage, GIL limitations

2. **Celery for Async Tasks**: Separate task queue system
   - Rejected: Additional complexity for current scale

3. **Go/Rust Rewrite**: Use language with better concurrency
   - Rejected: Team expertise is in Python

## References
- [FastAPI Async](https://fastapi.tiangolo.com/async/)
- [Python asyncio](https://docs.python.org/3/library/asyncio.html)