#!/bin/bash
set -e

BACKEND_PORT="${BACKEND_PORT:-8000}"
FRONTEND_PORT="${FRONTEND_PORT:-7860}"

# Create default .env from example if not mounted/provided
if [ ! -f .env ] && [ -f .env.example ]; then
    cp .env.example .env
    echo "[entrypoint] Created .env from .env.example"
fi

# Start backend API in background
uvicorn backend.app.main:app --host 0.0.0.0 --port "$BACKEND_PORT" &

# Start frontend (proxies /api/* to backend on 127.0.0.1:BACKEND_PORT)
export NEXT_SERVER_API_BASE_URL="http://127.0.0.1:${BACKEND_PORT}"
exec npm --prefix apps/web run start -- --port "$FRONTEND_PORT" --hostname 0.0.0.0
