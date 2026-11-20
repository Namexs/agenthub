#!/usr/bin/env bash
# AGENTHUB Phase 9 Workstream 4 — FORK DRY-RUN driver.
# Validates the 14-scenario live testnet test plan against a LOCAL anvil
# fork of BSC testnet (chain 97). NOTHING is broadcast to a real chain:
# all transactions land on the local fork only. All keys are PUBLIC
# anvil/test keys holding no real funds anywhere.
#
# Deviations from the live plan (documented in the dry-run report):
#  D1. Safe actions (admin/creator multisig) are sent with
#      `cast send --from <safe> --unlocked` (anvil impersonation)
#      instead of through the Safe web app with owner signatures.
#  D2. The 2-day timelock delays are skipped with anvil_increaseTime.
#  D3. There is no BscScan on a fork: event/revert verification uses
#      `cast logs` / `cast receipt` / `cast call` instead of BscScan pages.
#  D4. The two Safes are freshly deployed on the fork (canonical factory,
#      anvil accounts 1/2/3 as owners, threshold 2-of-3).
#
# Usage: ./run-fork-dryrun.sh   (writes fork-dryrun.log next to itself)
set -u
export PATH="$HOME/.foundry/bin:$PATH"
export TMPDIR="$HOME/workspace/.tmp"

DIR="$(cd "$(dirname "$0")" && pwd)"
CONTRACTS="$HOME/workspace/agenthub/packages/contracts"
RPC="http://127.0.0.1:8545"
FORK_URL="https://bsc-testnet-rpc.publicnode.com"
LOG="$DIR/fork-dryrun.log"
ANVIL_LOG="$DIR/anvil.log"
: > "$LOG"
exec > >(tee -a "$LOG") 2>&1

PASS=0; FAIL=0
log() { echo "[$(date '+%H:%M:%S')] $*"; }
check() { # check <name> <expected> <actual>
  if [ "$2" == "$3" ]; then PASS=$((PASS+1)); log "  PASS: $1 (expected=$2 actual=$3)";
  else FAIL=$((FAIL+1)); log "  FAIL: $1 (expected=$2 actual=$3)"; fi
}
check_contains() { # check_contains <name> <needle> <haystack>
  if [[ "$3" == *"$2"* ]]; then PASS=$((PASS+1)); log "  PASS: $1 (found $2)";
  else FAIL=$((FAIL+1)); log "  FAIL: $1 (missing $2 in: ${3:0:300})"; fi
}
now_ts() { cast block latest --field timestamp --rpc-url "$RPC" | tr -d '\r\n '; }

# --- Keys (PUBLIC anvil/test keys only) ---
MNEMONIC="test test test test test test test test test test test junk"
ANVIL0_KEY=$(cast wallet private-key --mnemonic "$MNEMONIC" --mnemonic-index 0)
ALICE_KEY=$(cast wallet private-key --mnemonic "$MNEMONIC" --mnemonic-index 1)
BOB_KEY=$(cast wallet private-key --mnemonic "$MNEMONIC" --mnemonic-index 2)
ALICE=$(cast wallet address --private-key "$ALICE_KEY")
BOB=$(cast wallet address --private-key "$BOB_KEY")
V1_KEY=0x$(printf '%064x' 0xA11CE5)
V2_KEY=0x$(printf '%064x' 0xBEEF2)
V1=$(cast wallet address --private-key "$V1_KEY")
V2=$(cast wallet address --private-key "$V2_KEY")
DEPLOYER=$(cast wallet address --private-key "$ANVIL0_KEY")
ZERO32=0x0000000000000000000000000000000000000000000000000000000000000000
ZERO_ADDR=0x0000000000000000000000000000000000000000
VERIFIER_ROLE=0x0ce23c3e399818cfee81a7ab0880f714e53d7672b08df0fa62f2843416e1ea09
CREATOR_ROLE=0x4112259a34054d6040a76e8d985093c9e8b0a52d820e856d7f4230fcaef428de
PAUSER_ROLE=0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a
SCORE_SOURCE_ROLE=0x08dd1ffd17984138218681c16863231d15b3a8b44885cf4e34e2804b0b15faa9
ISSUER_ROLE=0x114e74f6ea3bd819998f78687bfcb11b140da08e9b7d222fa9c1f1ba1f2aa122
BADGE_MANAGER_ROLE=0xa00144c395da084768e13ed238fd3b1cd040ce840901c1170be1eceffc7a7ded
PROPOSER_ROLE=0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1
EXECUTOR_ROLE=0xd8aa0f3194971a2a116679f7c2090f6939c8d4e01a2a8d7e41d55e5351469e63
CANCELLER_ROLE=0xfd643c72710c63c0180259aba6b2d05451e3591a24e58b62239378085726f783
DEFAULT_ADMIN_ROLE=0x0000000000000000000000000000000000000000000000000000000000000000

sign_attestation() { # <account> <questId> <nonce> <deadline> <key> -> prints sig
  local account="$1" qid="$2" nonce="$3" deadline="$4" key="$5"
  cat > "$DIR/.typed.json" <<EOF
{
  "types": {
    "EIP712Domain": [
      {"name": "name", "type": "string"},
      {"name": "version", "type": "string"},
      {"name": "chainId", "type": "uint256"},
      {"name": "verifyingContract", "type": "address"}
    ],
    "Attestation": [
      {"name": "account", "type": "address"},
      {"name": "questId", "type": "uint256"},
      {"name": "nonce", "type": "uint256"},
      {"name": "deadline", "type": "uint256"}
    ]
  },
  "primaryType": "Attestation",
  "domain": {"name": "AGENTHUB QuestManager", "version": "1", "chainId": 97, "verifyingContract": "$QM"},
  "message": {"account": "$account", "questId": $qid, "nonce": $nonce, "deadline": $deadline}
}
EOF
  cast wallet sign --data --from-file "$DIR/.typed.json" --private-key "$key"
}

warp_2days() {
  cast rpc anvil_increaseTime 172801 --rpc-url "$RPC" >/dev/null
  cast rpc anvil_mine 1 --rpc-url "$RPC" >/dev/null
  log "  (warped +2 days + 1s, new block time: $(now_ts))"
}

count_logs() { # <address> <event-sig> -> count
  cast logs --from-block "$DEPLOY_BLOCK" --to-block latest --address "$1" --rpc-url "$RPC" --json "$2" 2>/dev/null | jq -r 'length'
}

# send_raw <from> <to> <sig> [args...] -> tx hash (or empty).
# Sends via anvil eth_sendTransaction from an impersonated account, so a
# REVERTING call still lands on-chain with status 0 (cast send refuses
# to return a hash for a reverted tx). Used for the revert scenarios.
send_raw() {
  local from="$1" to="$2" sig="$3"; shift 3
  cast rpc anvil_impersonateAccount "$from" --rpc-url "$RPC" >/dev/null 2>&1
  local data
  data=$(cast calldata "$sig" "$@" 2>/dev/null) || { echo ""; return; }
  curl -s -X POST "$RPC" -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_sendTransaction\",\"params\":[{\"from\":\"$from\",\"to\":\"$to\",\"data\":\"$data\",\"gas\":\"0xF4240\"}]}" \
    | jq -r '.result // empty'
}

# --- 0. Start anvil fork ---
log "== 0. Starting anvil fork of BSC testnet (chain 97) =="
pkill -x anvil 2>/dev/null; sleep 1
anvil --fork-url "$FORK_URL" --port 8545 > "$ANVIL_LOG" 2>&1 &
ANVIL_PID=$!
trap 'kill $ANVIL_PID 2>/dev/null; rm -f "$DIR/.typed.json"' EXIT
for i in $(seq 1 30); do
  CHAIN=$(cast chain-id --rpc-url "$RPC" 2>/dev/null || echo "")
  [ "$CHAIN" == "97" ] && break
  sleep 2
done
check "fork chain-id" "97" "$CHAIN"
log "  factory code chars via fork: $(cast code 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67 --rpc-url "$RPC" | tr -d '\n' | wc -c) (expect ~6110)"
log "  singleton code chars via fork: $(cast code 0x41675C099F32341bf84BFc5382aF534df5C7461a --rpc-url "$RPC" | tr -d '\n' | wc -c) (expect ~47160)"
log "  alice=$ALICE bob=$BOB verifier1=$V1 verifier2=$V2 deployer=$DEPLOYER"

# --- 1. Deploy two genuine Safes on the fork ---
log "== 1. Deploying fork Safes (canonical factory v1.4.1, 2-of-3) =="
SAFES_OUT=$(cd "$CONTRACTS" && forge script "$DIR/DeployForkSafes.s.sol" --rpc-url "$RPC" --broadcast --private-key "$ANVIL0_KEY" 2>&1)
echo "$SAFES_OUT" | grep -E "ADMIN_SAFE|CREATOR_SAFE" | sed 's/^/  /'
ADMIN_SAFE=$(echo "$SAFES_OUT" | grep "ADMIN_SAFE:" | awk '{print $2}')
CREATOR_SAFE=$(echo "$SAFES_OUT" | grep "CREATOR_SAFE:" | awk '{print $2}')
[ -n "$ADMIN_SAFE" ] && [ -n "$CREATOR_SAFE" ] || { log "FATAL: Safe deploy failed"; echo "$SAFES_OUT" | tail -20; exit 1; }
check "admin safe threshold" "2" "$(cast call "$ADMIN_SAFE" "getThreshold()(uint256)" --rpc-url "$RPC")"
check "creator safe threshold" "2" "$(cast call "$CREATOR_SAFE" "getThreshold()(uint256)" --rpc-url "$RPC")"
# Fund the Safes so impersonated sends can pay gas, and impersonate
# them NOW: this cast version's `--unlocked` sends via
# eth_sendTransaction and anvil rejects it ("No Signer available")
# unless anvil_impersonateAccount was called first.
cast rpc anvil_setBalance "$ADMIN_SAFE" 0x56BC75E2D63100000 --rpc-url "$RPC" >/dev/null
cast rpc anvil_setBalance "$CREATOR_SAFE" 0x56BC75E2D63100000 --rpc-url "$RPC" >/dev/null
cast rpc anvil_impersonateAccount "$ADMIN_SAFE" --rpc-url "$RPC" >/dev/null
cast rpc anvil_impersonateAccount "$CREATOR_SAFE" --rpc-url "$RPC" >/dev/null

# --- 2. Deploy AGENTHUB (Scenario 1) ---
log "== S1. Deploying AGENTHUB via DeployAgentHub (broadcast on fork) =="
DEPLOY_BLOCK_BEFORE=$(cast block-number --rpc-url "$RPC")
DEPLOY_OUT=$(cd "$CONTRACTS" && DEPLOYER_PRIVATE_KEY="$ANVIL0_KEY" ADMIN_MULTISIG="$ADMIN_SAFE" QUEST_CREATOR="$CREATOR_SAFE" VERIFIER="$V1" CONFIRM_TESTNET_DEPLOY=true forge script script/DeployAgentHub.s.sol --rpc-url "$RPC" --broadcast 2>&1)
echo "$DEPLOY_OUT" | grep -E "MockAgentId:|AgentGate:|TimelockController:|Reputation:|Achievement:|QuestManager:" | sed 's/^/  /'
MOCK=$(echo "$DEPLOY_OUT" | grep "MockAgentId:" | awk '{print $2}')
GATE=$(echo "$DEPLOY_OUT" | grep "AgentGate:" | awk '{print $2}')
TIMELOCK=$(echo "$DEPLOY_OUT" | grep "TimelockController:" | awk '{print $2}')
REP=$(echo "$DEPLOY_OUT" | grep "Reputation:" | awk '{print $2}')
ACH=$(echo "$DEPLOY_OUT" | grep "Achievement:" | awk '{print $2}')
QM=$(echo "$DEPLOY_OUT" | grep "QuestManager:" | awk '{print $2}')
[ -n "$QM" ] || { log "FATAL: deploy failed"; echo "$DEPLOY_OUT" | tail -30; exit 1; }
DEPLOY_BLOCK=$((DEPLOY_BLOCK_BEFORE + 1))
DEPLOY_GAS=$(python3 -c "import json;d=json.load(open('$CONTRACTS/broadcast/DeployAgentHub.s.sol/97/run-latest.json'));print(sum(int(r['gasUsed'],0) for r in d['receipts']))" 2>/dev/null || echo "?")
log "  deploy block=$DEPLOY_BLOCK total gas=$DEPLOY_GAS"
log "  MOCK=$MOCK GATE=$GATE TIMELOCK=$TIMELOCK REP=$REP ACH=$ACH QM=$QM"

# --- S2: address verification ---
log "== S2. Verifying deployed addresses on-chain =="
check "gate.agentIdContract" "$MOCK" "$(cast call "$GATE" "agentIdContract()(address)" --rpc-url "$RPC")"
check "gate.expectedChainId" "97" "$(cast call "$GATE" "expectedChainId()(uint256)" --rpc-url "$RPC")"
check "qm.gate" "$GATE" "$(cast call "$QM" "gate()(address)" --rpc-url "$RPC")"
check "qm.reputation" "$REP" "$(cast call "$QM" "reputation()(address)" --rpc-url "$RPC")"
check "qm.achievement" "$ACH" "$(cast call "$QM" "achievement()(address)" --rpc-url "$RPC")"

# --- S3: ownership + roles ---
log "== S3. Verifying ownership + roles =="
check "mock.owner == admin safe" "$ADMIN_SAFE" "$(cast call "$MOCK" "owner()(address)" --rpc-url "$RPC")"
check "qm admin == timelock" "true" "$(cast call "$QM" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN_ROLE" "$TIMELOCK" --rpc-url "$RPC")"
check "rep admin == timelock" "true" "$(cast call "$REP" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN_ROLE" "$TIMELOCK" --rpc-url "$RPC")"
check "ach admin == timelock" "true" "$(cast call "$ACH" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN_ROLE" "$TIMELOCK" --rpc-url "$RPC")"
check "rep SCORE_SOURCE == qm" "true" "$(cast call "$REP" "hasRole(bytes32,address)(bool)" "$SCORE_SOURCE_ROLE" "$QM" --rpc-url "$RPC")"
check "ach ISSUER == qm" "true" "$(cast call "$ACH" "hasRole(bytes32,address)(bool)" "$ISSUER_ROLE" "$QM" --rpc-url "$RPC")"
check "ach BADGE_MANAGER == admin safe" "true" "$(cast call "$ACH" "hasRole(bytes32,address)(bool)" "$BADGE_MANAGER_ROLE" "$ADMIN_SAFE" --rpc-url "$RPC")"
check "qm CREATOR == creator safe" "true" "$(cast call "$QM" "hasRole(bytes32,address)(bool)" "$CREATOR_ROLE" "$CREATOR_SAFE" --rpc-url "$RPC")"
check "qm PAUSER == admin safe (default)" "true" "$(cast call "$QM" "hasRole(bytes32,address)(bool)" "$PAUSER_ROLE" "$ADMIN_SAFE" --rpc-url "$RPC")"
check "qm VERIFIER == v1" "true" "$(cast call "$QM" "hasRole(bytes32,address)(bool)" "$VERIFIER_ROLE" "$V1" --rpc-url "$RPC")"
check "deployer qm admin" "false" "$(cast call "$QM" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN_ROLE" "$DEPLOYER" --rpc-url "$RPC")"
check "deployer rep admin" "false" "$(cast call "$REP" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN_ROLE" "$DEPLOYER" --rpc-url "$RPC")"
check "deployer ach admin" "false" "$(cast call "$ACH" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN_ROLE" "$DEPLOYER" --rpc-url "$RPC")"
check "deployer timelock admin" "false" "$(cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN_ROLE" "$DEPLOYER" --rpc-url "$RPC")"
check "qm paused" "false" "$(cast call "$QM" "paused()(bool)" --rpc-url "$RPC")"
check "rep paused" "false" "$(cast call "$REP" "paused()(bool)" --rpc-url "$RPC")"
check "ach paused" "false" "$(cast call "$ACH" "paused()(bool)" --rpc-url "$RPC")"

# --- S4: timelock ---
log "== S4. Verifying timelock =="
check "timelock minDelay (2 days)" "172800" "$(cast call "$TIMELOCK" "getMinDelay()(uint256)" --rpc-url "$RPC" | awk '{print $1}')"
check "timelock PROPOSER == admin safe" "true" "$(cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$PROPOSER_ROLE" "$ADMIN_SAFE" --rpc-url "$RPC")"
check "timelock EXECUTOR == admin safe" "true" "$(cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$EXECUTOR_ROLE" "$ADMIN_SAFE" --rpc-url "$RPC")"
check "timelock CANCELLER == admin safe" "true" "$(cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$CANCELLER_ROLE" "$ADMIN_SAFE" --rpc-url "$RPC")"
check "timelock self-admin" "true" "$(cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN_ROLE" "$TIMELOCK" --rpc-url "$RPC")"
check "timelock multisig NOT admin" "false" "$(cast call "$TIMELOCK" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN_ROLE" "$ADMIN_SAFE" --rpc-url "$RPC")"

# --- Setup: mint test Agent IDs via admin Safe ---
log "== Setup. Minting test Agent IDs to alice + bob (admin Safe) =="
cast send "$MOCK" "mint(address)" "$ALICE" --from "$ADMIN_SAFE" --unlocked --rpc-url "$RPC" >/dev/null
cast send "$MOCK" "mint(address)" "$BOB" --from "$ADMIN_SAFE" --unlocked --rpc-url "$RPC" >/dev/null
check "gate.isAgentHolder(alice)" "true" "$(cast call "$GATE" "isAgentHolder(address)(bool)" "$ALICE" --rpc-url "$RPC")"
check "gate.isAgentHolder(bob)" "true" "$(cast call "$GATE" "isAgentHolder(address)(bool)" "$BOB" --rpc-url "$RPC")"
check "gate.isAgentHolder(deployer)" "false" "$(cast call "$GATE" "isAgentHolder(address)(bool)" "$DEPLOYER" --rpc-url "$RPC")"

# --- Setup: grant verifier 2 via timelock (needed before S7) ---
log "== Setup. Granting verifier 2 via timelock (schedule -> warp 2d -> execute) =="
GRANT_DATA=$(cast calldata "grantRole(bytes32,address)" "$VERIFIER_ROLE" "$V2")
SALT_G2=0x0000000000000000000000000000000000000000000000000000000000000001
cast send "$TIMELOCK" "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" "$QM" 0 "$GRANT_DATA" "$ZERO32" "$SALT_G2" 172800 --from "$ADMIN_SAFE" --unlocked --rpc-url "$RPC" >/dev/null
OP_G2=$(cast call "$TIMELOCK" "hashOperation(address,uint256,bytes,bytes32,bytes32)(bytes32)" "$QM" 0 "$GRANT_DATA" "$ZERO32" "$SALT_G2" --rpc-url "$RPC")
check "grant-v2 op state (1=Waiting)" "1" "$(cast call "$TIMELOCK" "getOperationState(bytes32)(uint8)" "$OP_G2" --rpc-url "$RPC")"
warp_2days
check "grant-v2 op state (2=Ready)" "2" "$(cast call "$TIMELOCK" "getOperationState(bytes32)(uint8)" "$OP_G2" --rpc-url "$RPC")"
cast send "$TIMELOCK" "execute(address,uint256,bytes,bytes32,bytes32)" "$QM" 0 "$GRANT_DATA" "$ZERO32" "$SALT_G2" --from "$ADMIN_SAFE" --unlocked --rpc-url "$RPC" >/dev/null
check "grant-v2 op state (3=Done)" "3" "$(cast call "$TIMELOCK" "getOperationState(bytes32)(uint8)" "$OP_G2" --rpc-url "$RPC")"
check "qm VERIFIER == v2" "true" "$(cast call "$QM" "hasRole(bytes32,address)(bool)" "$VERIFIER_ROLE" "$V2" --rpc-url "$RPC")"
check "verifierCount" "2" "$(cast call "$QM" "verifierCount()(uint256)" --rpc-url "$RPC")"

# --- S5: create Attested threshold-1 quest ---
log "== S5. Creating Attested threshold-1 quest (100 pts) =="
NOW=$(now_ts); START=$NOW; END=$((NOW + 30*86400))
cast send "$QM" "createQuest(string,string,uint8,uint8,address,uint256,uint256,uint256,uint256,uint256,uint8)" \
  "Smoke T1" "Fork dry-run threshold-1 quest" 1 2 "$ZERO_ADDR" 100 0 "$START" "$END" 0 1 \
  --from "$CREATOR_SAFE" --unlocked --rpc-url "$RPC" >/dev/null
Q1=$(cast call "$QM" "questCount()(uint256)" --rpc-url "$RPC")
check "quest 1 id" "1" "$Q1"
Q1_OUT=$(cast call "$QM" "getQuest(uint256)((uint256,address,string,string,uint8,uint8,address,uint256,uint256,uint256,uint256,uint256,uint256,bool,uint8))" 1 --rpc-url "$RPC" 2>&1)
log "  getQuest(1): $(echo "$Q1_OUT" | tr '\n' ' ' | head -c 400)"
check_contains "quest 1 reward 100 in getQuest" "100" "$Q1_OUT"

# --- S6: complete threshold-1 quest with one verifier ---
log "== S6. Completing quest 1 with one verifier signature =="
NONCE_A=$(cast call "$QM" "nonces(address)(uint256)" "$ALICE" --rpc-url "$RPC")
DL=$(( $(now_ts) + 86400 ))
SIG_A1=$(sign_attestation "$ALICE" 1 "$NONCE_A" "$DL" "$V1_KEY")
TX_S6=$(cast send "$QM" "completeQuestWithAttestation(uint256,uint256,bytes[])" 1 "$DL" "[$SIG_A1]" --private-key "$ALICE_KEY" --rpc-url "$RPC" --json 2>/dev/null | jq -r '.transactionHash')
log "  S6 tx: $TX_S6"
check "alice points after S6" "100" "$(cast call "$REP" "points(address)(uint256)" "$ALICE" --rpc-url "$RPC")"
check "alice hasCompleted q1" "true" "$(cast call "$QM" "hasCompleted(address,uint256)(bool)" "$ALICE" 1 --rpc-url "$RPC")"
check "alice nonce after S6" "1" "$(cast call "$QM" "nonces(address)(uint256)" "$ALICE" --rpc-url "$RPC")"

# --- S7: create Attested threshold-2 quest ---
log "== S7. Creating Attested threshold-2 quest (100 pts) =="
NOW=$(now_ts); START=$NOW; END=$((NOW + 30*86400))
cast send "$QM" "createQuest(string,string,uint8,uint8,address,uint256,uint256,uint256,uint256,uint256,uint8)" \
  "Smoke T2" "Fork dry-run threshold-2 quest" 1 2 "$ZERO_ADDR" 100 0 "$START" "$END" 0 2 \
  --from "$CREATOR_SAFE" --unlocked --rpc-url "$RPC" >/dev/null
Q2=$(cast call "$QM" "questCount()(uint256)" --rpc-url "$RPC")
check "quest 2 id" "2" "$Q2"
check "highestLiveThreshold" "2" "$(cast call "$QM" "highestLiveThreshold()(uint8)" --rpc-url "$RPC")"
check "liveAttestedQuestCount(2)" "1" "$(cast call "$QM" "liveAttestedQuestCount(uint8)(uint256)" 2 --rpc-url "$RPC")"

# --- S8: complete threshold-2 quest with two verifiers ---
log "== S8. Completing quest 2 with two verifier signatures =="
NONCE_A=$(cast call "$QM" "nonces(address)(uint256)" "$ALICE" --rpc-url "$RPC")
DL=$(( $(now_ts) + 86400 ))
SIG_A2A=$(sign_attestation "$ALICE" 2 "$NONCE_A" "$DL" "$V1_KEY")
SIG_A2B=$(sign_attestation "$ALICE" 2 "$NONCE_A" "$DL" "$V2_KEY")
TX_S8=$(cast send "$QM" "completeQuestWithAttestation(uint256,uint256,bytes[])" 2 "$DL" "[$SIG_A2A,$SIG_A2B]" --private-key "$ALICE_KEY" --rpc-url "$RPC" --json 2>/dev/null | jq -r '.transactionHash')
log "  S8 tx: $TX_S8"
check "alice points after S8" "200" "$(cast call "$REP" "points(address)(uint256)" "$ALICE" --rpc-url "$RPC")"
check "alice hasCompleted q2" "true" "$(cast call "$QM" "hasCompleted(address,uint256)(bool)" "$ALICE" 2 --rpc-url "$RPC")"
check "alice nonce after S8" "2" "$(cast call "$QM" "nonces(address)(uint256)" "$ALICE" --rpc-url "$RPC")"

# --- S9: duplicate signature rejected ---
log "== S9. Duplicate signer on quest 2 (bob) must revert =="
NONCE_B=$(cast call "$QM" "nonces(address)(uint256)" "$BOB" --rpc-url "$RPC")
DL=$(( $(now_ts) + 86400 ))
SIG_B=$(sign_attestation "$BOB" 2 "$NONCE_B" "$DL" "$V1_KEY")
REV9=$(cast call "$QM" "completeQuestWithAttestation(uint256,uint256,bytes[])" 2 "$DL" "[$SIG_B,$SIG_B]" --from "$BOB" --rpc-url "$RPC" 2>&1)
log "  cast call output: $REV9"
check_contains "S9 revert selector DuplicateAttestationSigner 0x168e588e" "0x168e588e" "$REV9"
TX_S9=$(send_raw "$BOB" "$QM" "completeQuestWithAttestation(uint256,uint256,bytes[])" 2 "$DL" "[$SIG_B,$SIG_B]")
if [ -n "$TX_S9" ]; then
  sleep 1
  check "S9 on-chain tx status (0=failed)" "0x0" "$(cast receipt "$TX_S9" --json --rpc-url "$RPC" 2>/dev/null | jq -r '.status // empty')"
  log "  S9 failed tx: $TX_S9"
else log "  (S9 send produced no tx hash — cast refused to broadcast)"; fi
check "bob points after S9 (unchanged)" "0" "$(cast call "$REP" "points(address)(uint256)" "$BOB" --rpc-url "$RPC")"
check "bob nonce after S9 (not burned)" "0" "$(cast call "$QM" "nonces(address)(uint256)" "$BOB" --rpc-url "$RPC")"

# --- S10: insufficient signatures rejected ---
log "== S10. One signature on threshold-2 quest (bob) must revert =="
REV10=$(cast call "$QM" "completeQuestWithAttestation(uint256,uint256,bytes[])" 2 "$DL" "[$SIG_B]" --from "$BOB" --rpc-url "$RPC" 2>&1)
log "  cast call output: $REV10"
check_contains "S10 revert selector InsufficientAttestations 0x78da11c2" "0x78da11c2" "$REV10"
TX_S10=$(send_raw "$BOB" "$QM" "completeQuestWithAttestation(uint256,uint256,bytes[])" 2 "$DL" "[$SIG_B]")
if [ -n "$TX_S10" ]; then
  sleep 1
  check "S10 on-chain tx status (0=failed)" "0x0" "$(cast receipt "$TX_S10" --json --rpc-url "$RPC" 2>/dev/null | jq -r '.status // empty')"
  log "  S10 failed tx: $TX_S10"
else log "  (S10 send produced no tx hash — cast refused to broadcast)"; fi
check "bob points after S10 (unchanged)" "0" "$(cast call "$REP" "points(address)(uint256)" "$BOB" --rpc-url "$RPC")"
check "bob nonce after S10 (not burned)" "0" "$(cast call "$QM" "nonces(address)(uint256)" "$BOB" --rpc-url "$RPC")"

# --- S11: 1,001-point threshold-1 quest rejected (H01) + positive controls ---
log "== S11. Quest 1,001 pts threshold 1 must revert (H01) =="
NOW=$(now_ts); START=$NOW; END=$((NOW + 30*86400))
REV11=$(cast call "$QM" "createQuest(string,string,uint8,uint8,address,uint256,uint256,uint256,uint256,uint256,uint8)" \
  "High T1" "must revert" 1 2 "$ZERO_ADDR" 1001 0 "$START" "$END" 0 1 --from "$CREATOR_SAFE" --rpc-url "$RPC" 2>&1)
log "  cast call output: $REV11"
check_contains "S11 revert selector InsufficientAttestations 0x78da11c2" "0x78da11c2" "$REV11"
TX_S11=$(send_raw "$CREATOR_SAFE" "$QM" "createQuest(string,string,uint8,uint8,address,uint256,uint256,uint256,uint256,uint256,uint8)" \
  "High T1" "must revert" 1 2 "$ZERO_ADDR" 1001 0 "$START" "$END" 0 1)
if [ -n "$TX_S11" ]; then
  sleep 1
  check "S11 on-chain tx status (0=failed)" "0x0" "$(cast receipt "$TX_S11" --json --rpc-url "$RPC" 2>/dev/null | jq -r '.status // empty')"
  log "  S11 failed tx: $TX_S11"
else log "  (S11 send produced no tx hash — cast refused to broadcast)"; fi
check "questCount unchanged after S11" "2" "$(cast call "$QM" "questCount()(uint256)" --rpc-url "$RPC")"
log "  Positive controls: 1,001/T2 succeeds, 1,000/T1 succeeds"
cast send "$QM" "createQuest(string,string,uint8,uint8,address,uint256,uint256,uint256,uint256,uint256,uint8)" \
  "High T2" "control" 1 2 "$ZERO_ADDR" 1001 0 "$START" "$END" 0 2 --from "$CREATOR_SAFE" --unlocked --rpc-url "$RPC" >/dev/null
cast send "$QM" "createQuest(string,string,uint8,uint8,address,uint256,uint256,uint256,uint256,uint256,uint8)" \
  "Boundary T1" "control" 1 2 "$ZERO_ADDR" 1000 0 "$START" "$END" 0 1 --from "$CREATOR_SAFE" --unlocked --rpc-url "$RPC" >/dev/null
check "questCount after controls" "4" "$(cast call "$QM" "questCount()(uint256)" --rpc-url "$RPC")"

# --- S12: revoke guardrail (M01) ---
log "== S12. Revoke verifier 2 while T2 quests live must be blocked =="
REVOKE_DATA=$(cast calldata "revokeRole(bytes32,address)" "$VERIFIER_ROLE" "$V2")
SALT_RV=0x0000000000000000000000000000000000000000000000000000000000000003
cast send "$TIMELOCK" "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" "$QM" 0 "$REVOKE_DATA" "$ZERO32" "$SALT_RV" 172800 --from "$ADMIN_SAFE" --unlocked --rpc-url "$RPC" >/dev/null
OP_RV=$(cast call "$TIMELOCK" "hashOperation(address,uint256,bytes,bytes32,bytes32)(bytes32)" "$QM" 0 "$REVOKE_DATA" "$ZERO32" "$SALT_RV" --rpc-url "$RPC")
warp_2days
REV12=$(cast call "$TIMELOCK" "execute(address,uint256,bytes,bytes32,bytes32)" "$QM" 0 "$REVOKE_DATA" "$ZERO32" "$SALT_RV" --from "$ADMIN_SAFE" --rpc-url "$RPC" 2>&1)
log "  cast call output: $REV12"
check_contains "S12 revert selector RevocationWouldBrickQuest 0x8df6077d" "0x8df6077d" "$REV12"
TX_S12=$(send_raw "$ADMIN_SAFE" "$TIMELOCK" "execute(address,uint256,bytes,bytes32,bytes32)" "$QM" 0 "$REVOKE_DATA" "$ZERO32" "$SALT_RV")
if [ -n "$TX_S12" ]; then
  sleep 1
  check "S12 blocked-execute tx status (0=failed)" "0x0" "$(cast receipt "$TX_S12" --json --rpc-url "$RPC" 2>/dev/null | jq -r '.status // empty')"
  log "  S12 failed tx: $TX_S12"
else log "  (S12 send produced no tx hash — cast refused to broadcast)"; fi
check "S12 op still Ready (2) after failed execute" "2" "$(cast call "$TIMELOCK" "getOperationState(bytes32)(uint8)" "$OP_RV" --rpc-url "$RPC")"
check "v2 still holds VERIFIER_ROLE" "true" "$(cast call "$QM" "hasRole(bytes32,address)(bool)" "$VERIFIER_ROLE" "$V2" --rpc-url "$RPC")"
check "verifierCount still 2" "2" "$(cast call "$QM" "verifierCount()(uint256)" --rpc-url "$RPC")"
log "  Recovery: deactivate both live T2 quests (2 and 3), then re-execute the same operation"
cast send "$QM" "deactivateQuest(uint256)" 2 --from "$CREATOR_SAFE" --unlocked --rpc-url "$RPC" >/dev/null
cast send "$QM" "deactivateQuest(uint256)" 3 --from "$CREATOR_SAFE" --unlocked --rpc-url "$RPC" >/dev/null
check "highestLiveThreshold after deactivate" "1" "$(cast call "$QM" "highestLiveThreshold()(uint8)" --rpc-url "$RPC")"
cast send "$TIMELOCK" "execute(address,uint256,bytes,bytes32,bytes32)" "$QM" 0 "$REVOKE_DATA" "$ZERO32" "$SALT_RV" --from "$ADMIN_SAFE" --unlocked --rpc-url "$RPC" >/dev/null
check "S12 op Done (3) after re-execute" "3" "$(cast call "$TIMELOCK" "getOperationState(bytes32)(uint8)" "$OP_RV" --rpc-url "$RPC")"
check "v2 VERIFIER_ROLE revoked" "false" "$(cast call "$QM" "hasRole(bytes32,address)(bool)" "$VERIFIER_ROLE" "$V2" --rpc-url "$RPC")"
check "verifierCount after revoke" "1" "$(cast call "$QM" "verifierCount()(uint256)" --rpc-url "$RPC")"
log "  Recovery: re-grant verifier 2 via timelock (restore 2-verifier state)"
SALT_G2B=0x0000000000000000000000000000000000000000000000000000000000000004
cast send "$TIMELOCK" "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" "$QM" 0 "$GRANT_DATA" "$ZERO32" "$SALT_G2B" 172800 --from "$ADMIN_SAFE" --unlocked --rpc-url "$RPC" >/dev/null
warp_2days
cast send "$TIMELOCK" "execute(address,uint256,bytes,bytes32,bytes32)" "$QM" 0 "$GRANT_DATA" "$ZERO32" "$SALT_G2B" --from "$ADMIN_SAFE" --unlocked --rpc-url "$RPC" >/dev/null
check "verifierCount restored" "2" "$(cast call "$QM" "verifierCount()(uint256)" --rpc-url "$RPC")"

# --- S13: supersedes (L07) ---
log "== S13. Supersedes: recreate quest 2, link, alice blocked, bob completes =="
NOW=$(now_ts); START=$NOW; END=$((NOW + 30*86400))
cast send "$QM" "createQuest(string,string,uint8,uint8,address,uint256,uint256,uint256,uint256,uint256,uint8)" \
  "Smoke T1 recreate" "Recreate of quest 2" 1 2 "$ZERO_ADDR" 100 0 "$START" "$END" 0 1 \
  --from "$CREATOR_SAFE" --unlocked --rpc-url "$RPC" >/dev/null
Q5=$(cast call "$QM" "questCount()(uint256)" --rpc-url "$RPC")
check "quest 5 id" "5" "$Q5"
SUP_DATA=$(cast calldata "setSupersedes(uint256,uint256)" 5 2)
SALT_SUP=0x0000000000000000000000000000000000000000000000000000000000000005
cast send "$TIMELOCK" "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" "$QM" 0 "$SUP_DATA" "$ZERO32" "$SALT_SUP" 172800 --from "$ADMIN_SAFE" --unlocked --rpc-url "$RPC" >/dev/null
warp_2days
cast send "$TIMELOCK" "execute(address,uint256,bytes,bytes32,bytes32)" "$QM" 0 "$SUP_DATA" "$ZERO32" "$SALT_SUP" --from "$ADMIN_SAFE" --unlocked --rpc-url "$RPC" >/dev/null
check "supersedes(5) == 2" "2" "$(cast call "$QM" "supersedes(uint256)(uint256)" 5 --rpc-url "$RPC")"
NONCE_A=$(cast call "$QM" "nonces(address)(uint256)" "$ALICE" --rpc-url "$RPC")
DL=$(( $(now_ts) + 86400 ))
SIG_A5=$(sign_attestation "$ALICE" 5 "$NONCE_A" "$DL" "$V1_KEY")
REV13=$(cast call "$QM" "completeQuestWithAttestation(uint256,uint256,bytes[])" 5 "$DL" "[$SIG_A5]" --from "$ALICE" --rpc-url "$RPC" 2>&1)
log "  cast call output: $REV13"
check_contains "S13 revert selector AlreadyCompletedSupersededQuest 0x89c03273" "0x89c03273" "$REV13"
check "alice points after blocked S13 (unchanged)" "200" "$(cast call "$REP" "points(address)(uint256)" "$ALICE" --rpc-url "$RPC")"
check "alice nonce after blocked S13 (not burned)" "2" "$(cast call "$QM" "nonces(address)(uint256)" "$ALICE" --rpc-url "$RPC")"
NONCE_B=$(cast call "$QM" "nonces(address)(uint256)" "$BOB" --rpc-url "$RPC")
SIG_B5=$(sign_attestation "$BOB" 5 "$NONCE_B" "$DL" "$V1_KEY")
TX_S13=$(cast send "$QM" "completeQuestWithAttestation(uint256,uint256,bytes[])" 5 "$DL" "[$SIG_B5]" --private-key "$BOB_KEY" --rpc-url "$RPC" --json 2>/dev/null | jq -r '.transactionHash')
log "  S13 bob tx: $TX_S13"
check "bob points after S13" "100" "$(cast call "$REP" "points(address)(uint256)" "$BOB" --rpc-url "$RPC")"
check "bob hasCompleted q5" "true" "$(cast call "$QM" "hasCompleted(address,uint256)(bool)" "$BOB" 5 --rpc-url "$RPC")"

# --- S14: event verification (cast logs instead of BscScan) ---
log "== S14. Event counts from deploy block $DEPLOY_BLOCK (cast logs) =="
check "QuestCreated count" "5" "$(count_logs "$QM" "QuestCreated(uint256,address,uint8,uint8,uint256)")"
check "QuestCompleted count" "3" "$(count_logs "$QM" "QuestCompleted(uint256,address,uint256,uint256)")"
check "PointsAdded count" "3" "$(count_logs "$REP" "PointsAdded(address,uint256,uint256,uint256)")"
check "AttestationUsed count" "4" "$(count_logs "$QM" "AttestationUsed(address,uint256,uint256,address)")"
check "QuestDeactivated count" "2" "$(count_logs "$QM" "QuestDeactivated(uint256)")"
check "QuestSuperseded count" "1" "$(count_logs "$QM" "QuestSuperseded(uint256,uint256)")"
check "RoleGranted on QM count" "7" "$(count_logs "$QM" "RoleGranted(bytes32,address,address)")"
check "RoleRevoked on QM count" "2" "$(count_logs "$QM" "RoleRevoked(bytes32,address,address)")"
check "CallScheduled on timelock" "4" "$(count_logs "$TIMELOCK" "CallScheduled(bytes32,uint256,address,uint256,bytes,bytes32,uint256)")"
check "CallExecuted on timelock" "4" "$(count_logs "$TIMELOCK" "CallExecuted(bytes32,uint256,address,uint256,bytes)")"
check "OwnershipTransferred on mock" "2" "$(count_logs "$MOCK" "OwnershipTransferred(address,address)")"
# Gas spot-checks (informational, from receipts)
if [ -n "${TX_S6:-}" ]; then log "  gas S6 (T1 completion): $(cast receipt "$TX_S6" --json --rpc-url "$RPC" 2>/dev/null | jq -r '.gasUsed // empty')"; fi
if [ -n "${TX_S8:-}" ]; then log "  gas S8 (T2 completion): $(cast receipt "$TX_S8" --json --rpc-url "$RPC" 2>/dev/null | jq -r '.gasUsed // empty')"; fi

# --- Cleanup of fork broadcast artifacts (keep the repo tree clean) ---
rm -rf "$CONTRACTS/broadcast/DeployAgentHub.s.sol/97" "$CONTRACTS/broadcast/DeployForkSafes.s.sol/97" 2>/dev/null
rmdir "$CONTRACTS/broadcast/DeployAgentHub.s.sol" "$CONTRACTS/broadcast/DeployForkSafes.s.sol" "$CONTRACTS/broadcast" 2>/dev/null || true

log "== DRY-RUN COMPLETE: PASS=$PASS FAIL=$FAIL =="
log "Deployed (FORK ONLY, not real testnet): MOCK=$MOCK GATE=$GATE TIMELOCK=$TIMELOCK REP=$REP ACH=$ACH QM=$QM"
log "Safes (FORK ONLY): ADMIN=$ADMIN_SAFE CREATOR=$CREATOR_SAFE"
[ "$FAIL" -eq 0 ]
