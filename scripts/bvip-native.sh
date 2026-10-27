#!/usr/bin/env bash
# Run SupoClip natively (backend API + ARQ worker via uv venv, frontend via pnpm)
# against the Postgres/Redis containers from docker-compose. Usage:
#   scripts/bvip-native.sh start | stop | status
# Requires: `docker compose up -d postgres redis`, `uv sync --frozen --extra cpu`
# in backend/ and `pnpm install --frozen-lockfile` in frontend/.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${BVIP_LOG_DIR:-$ROOT/backend/logs}"
mkdir -p "$LOG_DIR" "$ROOT/backend/uploads" "$ROOT/backend/clips"

load_env() {
  set -a
  # shellcheck disable=SC1091
  . "$ROOT/.env"
  set +a
  export DATABASE_URL="postgresql+asyncpg://${POSTGRES_USER:-supoclip}:${POSTGRES_PASSWORD:-supoclip_password}@localhost:5432/${POSTGRES_DB:-supoclip}"
  export REDIS_HOST=localhost REDIS_PORT=6379
  export TEMP_DIR="$ROOT/backend/uploads" PYTHONPATH="$ROOT/backend" PYTHONUNBUFFERED=1
  # Frontend (Prisma uses the plain postgresql:// scheme).
  export FRONTEND_DATABASE_URL="postgresql://${POSTGRES_USER:-supoclip}:${POSTGRES_PASSWORD:-supoclip_password}@localhost:5432/${POSTGRES_DB:-supoclip}"
  export NEXT_PUBLIC_API_URL="${NEXT_PUBLIC_API_URL:-http://localhost:8000}" BACKEND_INTERNAL_URL=http://localhost:8000
  export NEXT_PUBLIC_SELF_HOST="${SELF_HOST:-true}" NEXT_TELEMETRY_DISABLED=1
  # ANTHROPIC_API_KEY is intentionally not set in .env: it comes from the host environment.
}

case "${1:-start}" in
  start)
    load_env
    cd "$ROOT/backend"
    SUPOCLIP_SERVICE=backend setsid nohup .venv/bin/uvicorn src.main:app --host 0.0.0.0 --port 8000 \
      > "$LOG_DIR/backend.log" 2>&1 &
    # The backend creates/migrates the schema on startup; start the worker only afterwards.
    for _ in $(seq 1 60); do curl -sf http://localhost:8000/health/db >/dev/null 2>&1 && break; sleep 2; done
    SUPOCLIP_SERVICE=worker setsid nohup .venv/bin/arq src.workers.tasks.WorkerSettings \
      > "$LOG_DIR/worker.log" 2>&1 &
    cd "$ROOT/frontend"
    DATABASE_URL="$FRONTEND_DATABASE_URL" NODE_ENV=development setsid nohup pnpm run dev \
      > "$LOG_DIR/frontend.log" 2>&1 &
    echo "backend -> http://localhost:8000 | frontend -> http://localhost:3107 (logs: $LOG_DIR)"
    ;;
  stop)
    for p in $(pgrep -f "[.]venv/bin/(arq|uvicorn)" || true; pgrep -f "[n]ext dev --turbopack" || true); do kill "$p" 2>/dev/null || true; done
    echo "stopped"
    ;;
  status)
    pgrep -af "[.]venv/bin/(arq|uvicorn)|[n]ext dev --turbopack" || echo "not running"
    curl -sf http://localhost:8000/health/db && echo || echo "api not healthy"
    curl -sf -o /dev/null http://localhost:3107/api/auth/get-session && echo "frontend ok" || echo "frontend not healthy"
    ;;
  *) echo "usage: $0 start|stop|status"; exit 1 ;;
esac
