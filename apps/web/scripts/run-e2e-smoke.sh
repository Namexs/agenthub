#!/usr/bin/env bash
# E2E smoke runner (Phase 8): production build -> next start -> playwright
# smoke checks -> stop. Saves a combined log to
# agenthub-final-pretestnet/logs/phase8-e2e-smoke.log.
#
# Requires the `playwright` package resolvable from apps/web (see
# scripts/e2e-smoke.mjs header). Playwright is a declared devDependency
# (Phase C) — no manual symlinks.
#
# Exit code: the pipeline status is captured and returned explicitly.
# (Before the Next.js 15 upgrade the script ended with a bare
# `echo "log saved"`, which masked ANY failure inside the block —
# including a failing Playwright run — as exit 0. The CI e2e job
# depends on this runner failing loudly.)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WEB="$ROOT/apps/web"
PORT=3100
LOG="$ROOT/agenthub-final-pretestnet/logs/phase8-e2e-smoke.log"
mkdir -p "$(dirname "$LOG")"

# Cleanup must kill the whole server process tree: `npx next start`
# spawns sh -> next-server, and killing only the npx PID orphans
# next-server on the port (this leaked a server on :3100 in Phase F).
# setsid gives the server its own process group; the PID is shared via
# a pidfile because the server starts inside the piped block (subshell).
SERVER_PIDFILE="$ROOT/.e2e-server.pid"
rm -f "$SERVER_PIDFILE"
cleanup() {
  if [ -f "$SERVER_PIDFILE" ]; then
    kill -- "-$(cat "$SERVER_PIDFILE")" 2>/dev/null || true
    rm -f "$SERVER_PIDFILE"
  fi
}
trap cleanup EXIT

{
  echo "=== E2E smoke run: $(date -u +%FT%TZ) ==="
  echo "--- next build ---"
  cd "$WEB" && NODE_OPTIONS=--max-old-space-size=1024 npx next build
  echo "--- starting next start on :$PORT ---"
  setsid npx next start -p "$PORT" > "$ROOT/.e2e-server.log" 2>&1 &
  echo $! > "$ROOT/.e2e-server.pid"
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
status=$?
echo "log saved: $LOG"
exit "$status"
