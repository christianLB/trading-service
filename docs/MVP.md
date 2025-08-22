# 📄 MVP - Definición y Aceptación

> **Propósito**: Alcance del MVP, criterios de aceptación, contratos, y pipeline a producción (NAS) con un solo comando.

## Alcance MVP

- **API**: `/healthz`, `/orders`, `/orders/{id}`, `/positions`, `/metrics`.
- **Risk**: límites duros (`MAX_POS_USD`, `MAX_DAILY_LOSS_USD`) + whitelist de símbolos.
- **Broker**: `DummyBroker` (sin dependencias externas) con fills instantáneos.
- **Persistence**: Postgres (órdenes/fills/positions) + Redis (colas) listos en Compose.
- **Reporting**: Webhook `order_filled` firmado + métricas básicas.

## Contratos

### POST /orders (Bearer)

```json
{
  "symbol": "BTC/USDT",
  "side": "buy",
  "type": "market|limit",
  "qty": 0.01,
  "limitPrice": null,
  "clientId": "k2600x-admin",
  "idempotencyKey": "uuid-…"
}
```

**200**

```json
{ "orderId": "ord_ab12cd34", "status": "accepted" }
```

### Webhook `order_filled`

```json
{
  "event": "order_filled",
  "orderId": "ord_ab12cd34",
  "symbol": "BTC/USDT",
  "filledQty": 0.01,
  "avgPrice": 58000.0,
  "ts": "2025-08-21T12:00:00Z"
}
```

Cabecera: `X-Signature: hex(hmacSHA256(body, WEBHOOK_SECRET))`.

## Criterios de Aceptación

- `GET /healthz` → **200**.
- `POST /orders` con token válido → **200** y orden persistida.
- Riesgo bloquea notional > `MAX_POS_USD` → **422** (`risk_blocked`).
- `GET /orders/{id}` devuelve estado correcto.
- Webhook `order_filled` se emite y firma válida.
- `/metrics` expone: `orders_total`, `fills_total`, `risk_blocks_total`.
- Tests unitarios: motor de riesgo + broker dummy.

## Pipeline → Producción (NAS)

- **Dockerfile multistage** (`dev` y `prod`).
- **Compose único** (`deploy/compose.yaml`) con perfiles `dev` y `prod`.
- **.env.dev / .env.prod**.
- **Makefile** con targets estándar y despliegue NAS.

### Pre‑setup NAS (una sola vez)

- Habilitar SSH en NAS.
- Crear usuario con permisos Docker.
- `ssh-copy-id usuario@nas` para clave.
- Variables de `.env.prod` completas.

### Comando único de despliegue

```bash
make nas-deploy
```

Hace: `docker --context nas compose --env-file .env.prod --profile prod up -d --build` (build + run en el NAS).

## Makefile — targets relevantes (referencia)

```makefile
DC_DEV = docker compose --env-file .env.dev --profile dev
DC_PROD = docker compose --env-file .env.prod --profile prod
DC_NAS = docker --context nas compose --env-file .env.prod --profile prod

.PHONY: dev-up dev-down logs health prod-build prod-up nas-setup nas-deploy

dev-up:
	$(DC_DEV) up -d --build

dev-down:
	$(DC_DEV) down -v

logs:
	$(DC_DEV) logs -f --tail=200

health:
	curl -sS http://localhost:8080/healthz | jq .

prod-build:
	$(DC_PROD) build

prod-up:
	$(DC_PROD) up -d

nas-setup:
	docker context create nas --docker "host=ssh://usuario@nas"
	docker context use nas

nas-deploy:
	$(DC_NAS) up -d --build
```

## Notas finales

- Cambios de API/eventos **siempre** con PR que toque `contracts/` y actualice OpenAPI.
- Tokens y secretos fuera del repo (usar Portainer/variables del NAS).
- Mantener `README` y `docs/MVP.md` como **fuente de verdad**.