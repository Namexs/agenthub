#!/usr/bin/env bash
# Anvil frontend-integration runner (Phase 7).
# Starts anvil, deploys the local test stack, runs the node checks and the
# vitest anvil test against the live chain, saves a combined log, kills
# anvil. Exit non-zero on any failure.
#
# Usage (from the repo root): apps/web/scripts/run-anvil-integration.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WEB="$ROOT/apps/web"
CONTRACTS="$ROOT/packages/contracts"
LOG="$ROOT/agenthub-final-pretestnet/logs/phase7-anvil-integration.log"
mkdir -p "$(dirname "$LOG")"
export PATH="$HOME/.foundry/bin:$PATH"

ANVIL_KEY0="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

anvil --port 8545 --silent > "$ROOT/.anvil.log" 2>&1 &
ANVIL_PID=$!
trap 'kill $ANVIL_PID 2>/dev/null || true' EXIT

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
  cd "$WEB"
  echo "=== node checks (viem, exact hook RPC patterns) ==="
  node scripts/anvil-integration.mjs
  echo "=== vitest anvil test (real frontend lib vs live chain) ==="
  ANVIL_DEPLOYMENT="$WEB/.anvil-deployment.json" npx vitest run lib/anvil-integration.test.ts
  echo "=== ALL ANVIL INTEGRATION CHECKS PASSED ==="
} 2>&1 | tee "$LOG"
