# Changelog

All notable changes to the Trading Service will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Comprehensive project documentation structure
- Development workflow guide with Git Flow strategy
- Testing strategy with coverage requirements
- Architecture documentation with system design
- Progress tracking system for sprints
- Architecture Decision Records (ADRs)

### Fixed
- Module import path issues in Docker deployment
- Container naming in docker-compose files

### Changed
- Updated port configuration from 8080 to 8085
- Improved deployment scripts for NAS

## [0.1.0] - 2025-08-22

### Added
- Initial MVP implementation
- Core REST API with FastAPI
  - `GET /healthz` - Health check endpoint
  - `POST /orders` - Order creation with risk validation
  - `GET /orders/{id}` - Order status retrieval
  - `GET /positions` - Current positions
  - `GET /metrics` - Prometheus metrics
- Risk management engine
  - Position limits (MAX_POS_USD)
  - Daily loss limits (MAX_DAILY_LOSS_USD)
  - Symbol whitelist validation
- DummyBroker for testing
- PostgreSQL database with SQLAlchemy ORM
- Redis for caching and queues
- Alembic database migrations
- Docker multi-stage builds
- Deployment automation to Synology NAS
- Bearer token authentication
- Prometheus metrics integration
- Comprehensive test suite
- Health monitoring system
- Backup and restore scripts

### Security
- API authentication with bearer tokens
- Environment-based secret management
- Webhook signature validation (planned)

### Infrastructure
- Docker Compose for local development
- Production deployment to Synology NAS
- Automated deployment scripts
- Database backup automation
- Health check monitoring

## [0.0.1] - 2025-08-21

### Added
- Initial project structure
- Basic FastAPI application
- Docker configuration
- PostgreSQL and Redis integration
- Development environment setup

---

## Version History Summary

| Version | Date | Highlights |
|---------|------|------------|
| 0.1.0 | 2025-08-22 | MVP release with core trading functionality |
| 0.0.1 | 2025-08-21 | Initial project setup |

## Upgrade Instructions

### From 0.0.1 to 0.1.0

1. **Database Migration**
   ```bash
   alembic upgrade head
   ```

2. **Environment Variables**
   - Add `MAX_POS_USD` and `MAX_DAILY_LOSS_USD` to `.env` files
   - Update `API_PORT` from 8080 to 8085

3. **Docker Images**
   ```bash
   make prod-build
   make nas-deploy
   ```

## Coming Soon (v0.2.0)

- [ ] CCXT integration for real exchanges
- [ ] Webhook implementation with retry logic
- [ ] WebSocket server for real-time updates
- [ ] Enhanced monitoring and alerting
- [ ] Automated backup scheduling
- [ ] Rate limiting improvements

## Support

For questions or issues, please refer to:
- [Documentation](./docs/)
- [GitHub Issues](https://github.com/christianLB/trading-service/issues)
- [Development Guide](./docs/DEVELOPMENT_WORKFLOW.md)