#!/usr/bin/env bash
# E2E smoke runner (Phase 8): production build -> next start -> playwright
# smoke checks -> stop. Saves a combined log to
# agenthub-final-pretestnet/logs/phase8-e2e-smoke.log.
#
# Requires the `playwright` package resolvable from apps/web (see
# scripts/e2e-smoke.mjs header). On this VM it is symlinked from
# ~/workspace/.tmp/test-deps/node_modules.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WEB="$ROOT/apps/web"
PORT=3100
LOG="$ROOT/agenthub-final-pretestnet/logs/phase8-e2e-smoke.log"
mkdir -p "$(dirname "$LOG")"

{
  echo "=== E2E smoke run: $(date -u +%FT%TZ) ==="
  echo "--- next build ---"
  cd "$WEB" && NODE_OPTIONS=--max-old-space-size=1024 npx next build
  echo "--- starting next start on :$PORT ---"
  npx next start -p "$PORT" > "$ROOT/.e2e-server.log" 2>&1 &
  SERVER_PID=$!
  trap 'kill $SERVER_PID 2>/dev/null || true' EXIT
  for i in $(seq 1 60); do
    if curl -sf -o /dev/null "http://127.0.0.1:$PORT/"; then
      echo "server ready after ${i}s"
      break
    fi
    sleep 1
    if [ "$i" = 60 ]; then echo "server did not start in 60s"; exit 1; fi
  done
  echo "--- playwright smoke ---"
  E2E_BASE_URL="http://127.0.0.1:$PORT" node scripts/e2e-smoke.mjs
} 2>&1 | tee "$LOG"
echo "log saved: $LOG"
