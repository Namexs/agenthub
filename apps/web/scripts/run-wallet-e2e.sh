#!/usr/bin/env bash
# Wallet E2E runner (Phase F): anvil -> deploy local test stack ->
# production build against the anvil deployment -> next start ->
# playwright wallet E2E (injected test wallet) -> stop.
# Saves a combined log to agenthub-final-release/logs/phase-f-wallet-e2e.log.
#
# Usage (from the repo root): apps/web/scripts/run-wallet-e2e.sh
# The test wallet is bob, anvil test account #2 (throwaway test key —
# see scripts/wallet-e2e.mjs). No production wallet or key is involved.
# pipefail: a failing Playwright run must fail this runner (without it,
# the pipeline exit status would be tee's, and failures would look green).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WEB="$ROOT/apps/web"
CONTRACTS="$ROOT/packages/contracts"
PORT=3101
LOG="$ROOT/agenthub-final-release/logs/phase-f-wallet-e2e.log"
mkdir -p "$(dirname "$LOG")"
export PATH="$HOME/.foundry/bin:$PATH"

ANVIL_KEY0="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

# Pre-flight: refuse to run if a previous anvil/server is still holding
# the ports — a stale server serving a rebuilt .next directory produces
# confusing failures (a rebuild while a server runs corrupts its chunks).
for PORT in 8545 "$PORT"; do
  if (command -v ss >/dev/null && ss -ltn 2>/dev/null | grep -q ":$PORT ") || curl -sf -o /dev/null "http://127.0.0.1:$PORT/"; then
    echo "ERROR: port $PORT is already in use — kill the stale anvil/next process first" >&2
    exit 1
  fi
done

anvil --port 8545 --silent > "$ROOT/.anvil-wallet-e2e.log" 2>&1 &
ANVIL_PID=$!
# The server starts inside the piped block below (a subshell), so its
# PID cannot be shared back to this shell — it is written to a pidfile
# instead. setsid gives it its own process group so cleanup kills the
# whole tree (npx -> sh -> next-server); killing only the npx PID
# orphans next-server, which then holds the port for the next run.
SERVER_PIDFILE="$ROOT/.wallet-e2e-server.pid"
rm -f "$SERVER_PIDFILE"
cleanup() {
  kill $ANVIL_PID 2>/dev/null || true
  if [ -f "$SERVER_PIDFILE" ]; then
    kill -- "-$(cat "$SERVER_PIDFILE")" 2>/dev/null || true
    rm -f "$SERVER_PIDFILE"
  fi
}
trap cleanup EXIT

for i in $(seq 1 30); do
  curl -sf -o /dev/null http://127.0.0.1:8545 && break || sleep 1
done

{
  echo "=== anvil up (pid $ANVIL_PID) ==="
  cd "$CONTRACTS"
  forge script script/DeployLocalTestStack.s.sol \
    --rpc-url http://127.0.0.1:8545 --broadcast --private-key "$ANVIL_KEY0"
  cp .anvil-deployment.json "$WEB/.anvil-deployment.json"
  echo "=== deployment ==="
  cat "$WEB/.anvil-deployment.json"
  echo "--- next build (against anvil deployment) ---"
  cd "$WEB"
  DEPLOY_JSON="$WEB/.anvil-deployment.json"
  export NEXT_PUBLIC_CHAIN_ID=31337
  export NEXT_PUBLIC_AGENT_ID_ADDRESS="$(python3 -c "import json;print(json.load(open('$DEPLOY_JSON'))['agentId'])")"
  export NEXT_PUBLIC_AGENT_GATE_ADDRESS="$(python3 -c "import json;print(json.load(open('$DEPLOY_JSON'))['agentGate'])")"
  export NEXT_PUBLIC_QUEST_MANAGER_ADDRESS="$(python3 -c "import json;print(json.load(open('$DEPLOY_JSON'))['questManager'])")"
  export NEXT_PUBLIC_REPUTATION_ADDRESS="$(python3 -c "import json;print(json.load(open('$DEPLOY_JSON'))['reputation'])")"
  export NEXT_PUBLIC_ACHIEVEMENT_ADDRESS="$(python3 -c "import json;print(json.load(open('$DEPLOY_JSON'))['achievement'])")"
  export NEXT_PUBLIC_DEPLOY_BLOCK="$(python3 -c "import json;print(json.load(open('$DEPLOY_JSON'))['deployBlock'])")"
  NODE_OPTIONS=--max-old-space-size=1024 npx next build
  echo "--- starting next start on :$PORT ---"
  setsid npx next start -p "$PORT" > "$ROOT/.wallet-e2e-server.log" 2>&1 &
  echo $! > "$ROOT/.wallet-e2e-server.pid"
  for i in $(seq 1 60); do
    if curl -sf -o /dev/null "http://127.0.0.1:$PORT/"; then
      echo "server ready after ${i}s"
      break
    fi
    sleep 1
    if [ "$i" = 60 ]; then echo "server did not start in 60s"; exit 1; fi
  done
  echo "--- playwright wallet E2E ---"
  WALLET_E2E_BASE_URL="http://127.0.0.1:$PORT" node scripts/wallet-e2e.mjs
} 2>&1 | tee "$LOG"
# Exit code: the pipeline status is captured and returned explicitly.
# (Before the Next.js 15 upgrade the script ended with a bare
# `echo "log saved"`, which masked ANY failure inside the block as
# exit 0 despite `pipefail` — the echo ran last and succeeded. The
# CI e2e job depends on this runner failing loudly.)
status=$?
echo "log saved: $LOG"
exit "$status"
