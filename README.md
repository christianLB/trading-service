# 📄 Trading Service

> **Propósito**: Guía práctica de uso rápido, estructura, endpoints y despliegue (incluye despliegue al NAS con **un solo comando** una vez hecho el setup).

## Descripción

`trading-service` es un microservicio determinista que recibe órdenes, aplica un motor de riesgo, ejecuta en un broker (dummy/ccxt), persiste estado y reporta por webhooks y métricas. Es agnóstico del origen de señales y **no** incluye LLMs ni UI.

## Endpoints (MVP)

- `GET /healthz` — liveness.
- `POST /orders` — crea/valida/ejecuta una orden (Bearer).
- `GET /orders/{id}` — estado.
- `GET /positions` — snapshot de posiciones.
- `GET /metrics` — Prometheus.

## Configuración

Copiá `.env.sample` a `.env.dev` y `.env.prod`.

```env
APP_ENV=dev
API_PORT=8080
DATABASE_URL=postgresql+psycopg://postgres:postgres@db:5432/trading
REDIS_URL=redis://redis:6379/0
BROKER=dummy
EXCHANGE=binance
API_KEY=
API_SECRET=
API_TOKEN=change_me
WEBHOOK_URL=http://host.docker.internal:3000/_hooks/trading
WEBHOOK_SECRET=change_me
MAX_POS_USD=5000
MAX_DAILY_LOSS_USD=500
```

## Desarrollo local

```bash
make dev-up
make health
curl -H "Authorization: Bearer change_me" -H "Content-Type: application/json" \
  -d '{"symbol":"BTC/USDT","side":"buy","type":"market","qty":0.01}' \
  http://localhost:8080/orders
make logs
```

## Despliegue en producción (local)

```bash
make prod-build
make prod-up
```

## 🚀 Despliegue en NAS (Synology) — **un solo comando**

Primero hacé el setup una única vez:

```bash
make nas-setup   # crea contexto Docker remoto "nas" via SSH
```

Luego, cada release al NAS se hace con **un solo comando**:

```bash
make nas-deploy
```

Esto ejecuta en el NAS: build de imágenes en modo `prod` + `compose up -d` con el perfil `prod` y el `.env.prod`.

> **Nota**: asegurate de completar `.env.prod` con credenciales/URLs reales antes de `nas-deploy`.

## Estructura del proyecto

Ver [BOOTSTRAP.md](./BOOTSTRAP.md) para la estructura completa de carpetas y configuración inicial del repositorio.

## Seguridad

- `Authorization: Bearer <API_TOKEN>` obligatorio en endpoints mutantes.
- Webhooks con firma HMAC (cabecera `X-Signature` con hex de `HMAC_SHA256(body, WEBHOOK_SECRET)`).

## Roadmap breve

1. Persistencia real con SQLAlchemy/Alembic.
2. Adapter CCXT (Binance/Bybit).
3. Idempotencia robusta + reconciliación.
4. Kill‑switch y límites por símbolo.

## Documentación adicional

- [BOOTSTRAP.md](./BOOTSTRAP.md) - Configuración inicial y estructura del repositorio
- [docs/MVP.md](./docs/MVP.md) - Definición del MVP y criterios de aceptación