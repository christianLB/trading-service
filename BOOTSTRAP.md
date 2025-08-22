# 📄 BOOTSTRAP del Repositorio

> **Propósito**: Dejar el repo listo para trabajar sin embarrar la arquitectura. Define convenciones, estructura, entornos y comandos base. Este doc no describe el alcance funcional; eso está en el documento de MVP.

## 1) Convenciones y alcance del repo

- **Nombre**: `trading-service` (microservicio aislado, sin UI y sin LLMs).
- **Responsabilidad**: recibir órdenes, validar riesgo, ejecutar vía broker adapter, persistir y reportar por webhooks/métricas.
- **Arquitectura inamovible**: `API → Risk → BrokerAdapter → Persistence → Reporting`.
- **Contrato primero**: schemas en `contracts/` gobiernan cambios en endpoints y eventos.

## 2) Estructura de carpetas

```
trading-service/
  apps/
    api/            # FastAPI (routers, deps, schemas, health/metrics)
    worker/         # loops/estrategias, jobs
    backtester/     # placeholder para offline
  pkg/
    infra/          # settings, db, redis, logging, webhooks
    brokers/        # BaseBroker, DummyBroker, CcxtBroker (luego)
    strategies/     # BaseStrategy + ejemplos (optativo)
    risk/           # limits/policy
    domain/         # modelos y repos
  contracts/        # openapi.yaml + *.json (signals, proposals, webhooks)
  deploy/
    docker/
      Dockerfile    # multistage (dev/prod)
    compose.yaml    # único, con profiles: [dev, prod]
  tests/
  .env.sample
  Makefile
  README.md         # documento 2
  docs/
    MVP.md          # documento 3
```

## 3) Entornos y perfiles

- **.env.dev** (desarrollo) y **.env.prod** (producción). Ejemplo en `.env.sample`.
- **Profiles Compose**: `dev` para hot‑reload y bind mounts; `prod` para imagen optimizada.
- **Dockerfile multistage**: targets `dev` y `prod`.

## 4) Flujo de trabajo (git y PRs)

- **main** protegido. **feat/** para features, **fix/** para hotfixes.
- Cada cambio que afecte API/eventos **debe tocar `contracts/`** y versionar OpenAPI.
- No se mergea si no pasan: lint, tests, build.

## 5) Comandos estándar (Makefile)

- `make dev-up` / `make dev-down` → levanta/derriba entorno dev.
- `make logs` → logs seguidos.
- `make health` → chequeo `/healthz`.
- `make prod-build` → build imágenes modo prod.
- `make prod-up` → levanta perfil prod **en local**.
- `make nas-setup` → (una sola vez) crea contexto Docker remoto al NAS.
- `make nas-deploy` → **un solo comando** para desplegar en NAS (build+up con perfil prod).

## 6) Requisitos mínimos del host

- Docker >= 24, Compose v2.
- En NAS (Synology): Docker/Container Manager activo; usuario con permisos; red local accesible por SSH.

## 7) Seguridad inicial

- Tokens/secretos **no** en repo. Usar `.env.*` locales o secretos del NAS/Portainer.
- Webhooks firmados con HMAC del body (`WEBHOOK_SECRET`).