# 🤝 Contributing Guide

Thank you for your interest in contributing to the Trading Service! This guide will help you get started.

## Table of Contents
- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Submitting Changes](#submitting-changes)
- [Style Guidelines](#style-guidelines)
- [Testing](#testing)

## Code of Conduct

- Be respectful and inclusive
- Welcome newcomers and help them get started
- Focus on constructive criticism
- Respect differing viewpoints and experiences

## Getting Started

1. **Fork the Repository**
   ```bash
   # Fork on GitHub, then:
   git clone https://github.com/YOUR_USERNAME/trading-service.git
   cd trading-service
   git remote add upstream https://github.com/christianLB/trading-service.git
   ```

2. **Set Up Development Environment**
   ```bash
   # Copy environment file
   cp .env.sample .env.dev
   
   # Start services
   make dev-up
   
   # Verify setup
   make health
   ```

3. **Create a Branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

## Development Setup

### Prerequisites
- Python 3.10+
- Docker & Docker Compose
- Poetry (optional, for local development)
- Make

### Local Development

```bash
# Install dependencies
pip install poetry
poetry install

# Install pre-commit hooks
pre-commit install

# Run tests
pytest

# Format code
black .
ruff check . --fix
```

### Docker Development

```bash
# Start all services
make dev-up

# View logs
make logs

# Run tests in container
docker compose exec api pytest

# Stop services
make dev-down
```

## Making Changes

### 1. Find an Issue
- Check [open issues](https://github.com/christianLB/trading-service/issues)
- Comment on the issue to claim it
- Create a new issue if needed

### 2. Write Code
- Follow the [architecture guidelines](../ARCHITECTURE.md)
- Add tests for new functionality
- Update documentation as needed
- Keep commits small and focused

### 3. Commit Messages
Use [Conventional Commits](https://www.conventionalcommits.org/):
```bash
feat: add CCXT broker for Binance
fix: correct position calculation bug
docs: update API documentation
test: add risk engine unit tests
refactor: simplify order validation logic
```

## Submitting Changes

### Pull Request Process

1. **Update Your Branch**
   ```bash
   git fetch upstream
   git rebase upstream/develop
   ```

2. **Run Tests**
   ```bash
   make test
   pytest --cov=apps --cov=pkg
   ```

3. **Create Pull Request**
   - Target the `develop` branch
   - Fill out the PR template completely
   - Link related issues
   - Add screenshots if UI changes

### PR Checklist
- [ ] Tests pass locally
- [ ] Code follows style guidelines
- [ ] Documentation updated
- [ ] No sensitive data committed
- [ ] PR description is clear
- [ ] Linked to issue

### Review Process
1. Automated checks must pass
2. At least one approval required
3. Address all feedback
4. Maintainer will merge when ready

## Style Guidelines

### Python Style

```python
# Good: Clear, typed, documented
from typing import Optional

async def calculate_position_size(
    balance: float,
    risk_percent: float,
    stop_loss: float
) -> Optional[float]:
    """
    Calculate position size based on risk management rules.
    
    Args:
        balance: Account balance in USD
        risk_percent: Risk percentage per trade (0-100)
        stop_loss: Stop loss distance in price units
        
    Returns:
        Position size in base units, or None if invalid
    """
    if risk_percent <= 0 or risk_percent > 100:
        return None
        
    risk_amount = balance * (risk_percent / 100)
    position_size = risk_amount / stop_loss
    
    return position_size
```

### Import Order
1. Standard library imports
2. Third-party imports
3. Local imports

```python
import asyncio
from typing import List, Optional

from fastapi import FastAPI, HTTPException
from sqlalchemy import select

from apps.api.schemas import OrderRequest
from pkg.domain.models import Order
```

### File Naming
- `snake_case.py` for Python files
- `PascalCase` for classes
- `UPPER_CASE` for constants

## Testing

### Test Requirements
- Write tests for all new features
- Maintain 85% code coverage
- Use meaningful test names
- Test edge cases

### Running Tests

```bash
# All tests
pytest

# Specific test file
pytest tests/unit/test_risk_engine.py

# With coverage
pytest --cov=apps --cov=pkg --cov-report=html

# Only unit tests
pytest -m unit

# Run in parallel
pytest -n auto
```

### Test Structure

```python
# tests/unit/test_feature.py
import pytest
from unittest.mock import Mock, patch

class TestFeature:
    """Test suite for Feature."""
    
    @pytest.fixture
    def setup(self):
        """Set up test fixtures."""
        return {...}
    
    def test_success_case(self, setup):
        """Test normal operation."""
        assert feature.process(setup['input']) == expected
    
    def test_edge_case(self):
        """Test boundary conditions."""
        with pytest.raises(ValueError):
            feature.process(invalid_input)
    
    @patch('external.service')
    def test_with_mock(self, mock_service):
        """Test with external dependency mocked."""
        mock_service.return_value = Mock(status=200)
        assert feature.call_service() == expected
```

## Documentation

### Where to Document
- **Code**: Docstrings for all public functions
- **API**: Update OpenAPI specification
- **Features**: Update relevant .md files
- **Decisions**: Create ADR if architectural

### Documentation Style

```python
def function_name(param1: str, param2: int) -> bool:
    """
    Brief description of what the function does.
    
    Longer description if needed, explaining the purpose,
    algorithm, or important details.
    
    Args:
        param1: Description of first parameter
        param2: Description of second parameter
        
    Returns:
        Description of return value
        
    Raises:
        ValueError: When param1 is empty
        TypeError: When param2 is not an integer
        
    Example:
        >>> function_name("test", 42)
        True
    """
```

## Getting Help

- 📖 Read the [documentation](../README.md)
- 💬 Ask in [GitHub Discussions](#)
- 🐛 Report bugs in [Issues](https://github.com/christianLB/trading-service/issues)
- 📧 Contact maintainers

## Recognition

Contributors will be:
- Listed in CONTRIBUTORS.md
- Mentioned in release notes
- Given credit in commit co-authors

Thank you for contributing! 🎉