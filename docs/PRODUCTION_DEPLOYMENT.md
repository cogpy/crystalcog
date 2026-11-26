# CrystalCog Production Deployment

The supported production deployment is the Crystal Pygmalion platform described
by `Dockerfile.production` and `docker-compose.production.yml`. It contains the
Galatea API/frontend server, Paphos JSON backend, and a configured
OpenAI-compatible inference endpoint. The legacy PostgreSQL, Redis, Nginx,
Kubernetes, Python, and CMake deployment contracts are not part of this path.

## Required configuration

Generate independent signing secrets and provide an inference service:

```bash
export SECRET_KEY_BASE="$(openssl rand -hex 32)"
export JWT_SECRET="$(openssl rand -hex 32)"
export APHRODITE_URL="http://inference.example:8000"
docker compose -f docker-compose.production.yml up --build -d
```

The container fails closed when either signing secret is absent in production.
Paphos accounts, chats, and event journals are persisted in the
`crystalcog_app-data` volume.

The Compose service binds Galatea to `127.0.0.1` so a TLS reverse proxy owns the
public listener. Paphos is internal to the Compose network and is not published.
The image contains a basic status page. To serve a built Galatea web application,
mount that directory and set `GALATEA_STATIC_DIR` to its container path.

## Automated operations

The existing Make and deployment script entry points use this same contract:

```bash
make production-build
make production-up
make production-status
make production-backup
make production-rollback
make production-down
```

Backups archive the active Paphos data volume. Rollback restores that archive
before restarting the service. `scripts/production/deploy.sh` supports
`deploy`, `status`, `logs`, `stop`, `backup`, and `rollback`; it accepts the
standard `.env.production` file.

## CogServer

CogServer is deployed separately from the Pygmalion platform. A non-loopback or
production bind requires `COGSERVER_AUTH_TOKEN`. HTTP and WebSocket-native clients
send it as a bearer token. Browser WebSocket clients first POST to
`/monitor-ticket` with bearer authentication and connect with the returned
single-use, five-minute ticket.

Telnet clients authenticate with:

```text
auth <token>
```

The HTTP compatibility command endpoint on the Telnet port accepts
`Authorization: Bearer <token>` and does not accept credentials in query strings.
Configure limits with `COGSERVER_MAX_BODY_BYTES`, `COGSERVER_RATE_CAPACITY`, and
`COGSERVER_RATE_REFILL`.

## Validation

Before deployment, run:

```bash
./scripts/verify.sh all
docker build -f Dockerfile.production --target runtime -t crystalcog/app:production .
```

The strict verifier checks formatting, all declared targets, the full spec
suite, and the CLI/HTTP/Telnet/WebSocket smoke tests.
