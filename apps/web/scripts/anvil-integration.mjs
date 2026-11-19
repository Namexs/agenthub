// Anvil integration checks (Phase 7) — raw viem checks against a live
// local deployment. This script exercises the EXACT RPC patterns the
// frontend hooks use (same functions, same events, same log ranges) and
// asserts the results. It runs after DeployLocalTestStack.s.sol via
// run-anvil-integration.sh.
//
// The keys below are PUBLIC anvil/test keys (anvil default accounts +
// the AttestationTest verifier key). They hold no real funds anywhere
// and are only ever used against the local anvil instance.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createPublicClient, createWalletClient, http, recoverTypedDataAddress } from 'viem';
import { anvil } from 'viem/chains';
import { privateKeyToAccount } from 'viem/accounts';

const here = dirname(fileURLToPath(import.meta.url));
const deployment = JSON.parse(readFileSync(join(here, '..', '.anvil-deployment.json'), 'utf8'));
const contractsOut = join(here, '..', '..', '..', 'packages', 'contracts', 'out');
const abiOf = (name) =>
  JSON.parse(readFileSync(join(contractsOut, `${name}.sol`, `${name}.json`), 'utf8')).abi;

const AGENT_GATE_ABI = abiOf('AgentGate');
const QUEST_MANAGER_ABI = abiOf('QuestManager');
const REPUTATION_ABI = abiOf('Reputation');
const ACHIEVEMENT_ABI = abiOf('Achievement');

const DEPLOYER_KEY = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
const ALICE_KEY = '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d';
const VERIFIER_KEY = '0x0000000000000000000000000000000000000000000000000000000000a11ce5';
// PHASE 6 (R-010): second verifier — q3 is a threshold-2 quest now.
const VERIFIER2_KEY = '0x0000000000000000000000000000000000000000000000000000000000a11ce6';

const publicClient = createPublicClient({ chain: anvil, transport: http('http://127.0.0.1:8545') });

let passed = 0;
let failed = 0;
function check(name, cond, extra = '') {
  if (cond) {
    passed++;
    console.log(`PASS ${name}`);
  } else {
    failed++;
    console.log(`FAIL ${name} ${extra}`);
  }
}
const eq = (a, b) => String(a) === String(b);

const d = deployment;
const fromBlock = BigInt(d.deployBlock);

// 1. Chain + gate
check('chainId is 31337', (await publicClient.getChainId()) === 31337);
const aliceHolder = await publicClient.readContract({
  address: d.agentGate,
  abi: AGENT_GATE_ABI,
  functionName: 'isAgentHolder',
  args: [d.alice],
});
check('isAgentHolder(alice) is true', aliceHolder === true);
const deployerHolder = await publicClient.readContract({
  address: d.agentGate,
  abi: AGENT_GATE_ABI,
  functionName: 'isAgentHolder',
  args: [d.deployer],
});
check('isAgentHolder(deployer) is false', deployerHolder === false);

// 2. Quests
const count = await publicClient.readContract({
  address: d.questManager,
  abi: QUEST_MANAGER_ABI,
  functionName: 'questCount',
});
check('questCount is 3', eq(count, 3), `(got ${count})`);

const q1 = await publicClient.readContract({
  address: d.questManager,
  abi: QUEST_MANAGER_ABI,
  functionName: 'getQuest',
  args: [1n],
});
check(
  'quest 1 is CheckIn "First Steps" 50pts badge 1',
  q1.title === 'First Steps' &&
    q1.validationKind === 0 &&
    eq(q1.rewardPoints, 50) &&
    eq(q1.badgeId, 1),
);
const q2 = await publicClient.readContract({
  address: d.questManager,
  abi: QUEST_MANAGER_ABI,
  functionName: 'getQuest',
  args: [2n],
});
check(
  'quest 2 is OnChain with the validator',
  q2.validationKind === 1 && q2.validator.toLowerCase() === d.validator.toLowerCase(),
);
const q3 = await publicClient.readContract({
  address: d.questManager,
  abi: QUEST_MANAGER_ABI,
  functionName: 'getQuest',
  args: [3n],
});
check('quest 3 is Attested', q3.validationKind === 2);
check(
  'quest 3 is threshold-2 (Phase 6)',
  Number(q3.attestationThreshold) === 2,
  `(got ${q3.attestationThreshold})`,
);
check('quest 1 is threshold-1', Number(q1.attestationThreshold) === 1);
check(
  'verifier2 key matches the deployment JSON',
  privateKeyToAccount(VERIFIER2_KEY).address.toLowerCase() === d.verifier2.toLowerCase(),
);

// 3. Completion state
for (const id of [1n, 2n, 3n]) {
  const done = await publicClient.readContract({
    address: d.questManager,
    abi: QUEST_MANAGER_ABI,
    functionName: 'hasCompleted',
    args: [d.alice, id],
  });
  check(`hasCompleted(alice, ${id}) is true`, done === true);
}
const bobDone = await publicClient.readContract({
  address: d.questManager,
  abi: QUEST_MANAGER_ABI,
  functionName: 'hasCompleted',
  args: [d.bob, 1n],
});
check('hasCompleted(bob, 1) is false', bobDone === false);

// 4. Reputation
const alicePoints = await publicClient.readContract({
  address: d.reputation,
  abi: REPUTATION_ABI,
  functionName: 'points',
  args: [d.alice],
});
check('points(alice) is 250', eq(alicePoints, 250), `(got ${alicePoints})`);
const aliceLevel = await publicClient.readContract({
  address: d.reputation,
  abi: REPUTATION_ABI,
  functionName: 'level',
  args: [d.alice],
});
check('level(alice) is 2 (1-based: 250 pts >= 100)', eq(aliceLevel, 2), `(got ${aliceLevel})`);
const aliceEvents = await publicClient.readContract({
  address: d.reputation,
  abi: REPUTATION_ABI,
  functionName: 'totalEvents',
  args: [d.alice],
});
check('totalEvents(alice) is 3', eq(aliceEvents, 3), `(got ${aliceEvents})`);

// 5. Event logs (the exact queries the hooks run)
const completedLogs = await publicClient.getLogs({
  address: d.questManager,
  event: {
    type: 'event',
    name: 'QuestCompleted',
    inputs: [
      { type: 'uint256', indexed: true, name: 'questId' },
      { type: 'address', indexed: true, name: 'account' },
      { type: 'uint256', indexed: false, name: 'rewardPoints' },
      { type: 'uint256', indexed: false, name: 'badgeTokenId' },
    ],
  },
  fromBlock,
  toBlock: 'latest',
});
check(
  'QuestCompleted logs: 3, all alice',
  completedLogs.length === 3 &&
    completedLogs.every((l) => l.args.account.toLowerCase() === d.alice.toLowerCase()),
  `(got ${completedLogs.length})`,
);

const pointsLogs = await publicClient.getLogs({
  address: d.reputation,
  event: {
    type: 'event',
    name: 'PointsAdded',
    inputs: [
      { type: 'address', indexed: true, name: 'account' },
      { type: 'uint256', indexed: true, name: 'questId' },
      { type: 'uint256', indexed: false, name: 'points' },
      { type: 'uint256', indexed: false, name: 'newTotal' },
    ],
  },
  fromBlock,
  toBlock: 'latest',
});
const pointsSum = pointsLogs.reduce((sum, l) => sum + Number(l.args.points), 0);
check(
  'PointsAdded logs sum to 250',
  pointsLogs.length === 3 && pointsSum === 250,
  `(got ${pointsLogs.length} logs, sum ${pointsSum})`,
);

const badgeLogs = await publicClient.getLogs({
  address: d.achievement,
  event: {
    type: 'event',
    name: 'BadgeIssued',
    inputs: [
      { type: 'address', indexed: true, name: 'account' },
      { type: 'uint256', indexed: true, name: 'badgeId' },
      { type: 'uint256', indexed: true, name: 'tokenId' },
    ],
  },
  args: { account: d.alice },
  fromBlock,
  toBlock: 'latest',
});
check(
  'BadgeIssued logs for alice: 2 (badges 1+2)',
  badgeLogs.length === 2 &&
    badgeLogs
      .map((l) => Number(l.args.badgeId))
      .sort()
      .join() === '1,2',
  `(got ${badgeLogs.length})`,
);

const definedLogs = await publicClient.getLogs({
  address: d.achievement,
  event: {
    type: 'event',
    name: 'BadgeDefined',
    inputs: [
      { type: 'uint256', indexed: true, name: 'badgeId' },
      { type: 'string', indexed: false, name: 'name' },
      { type: 'string', indexed: false, name: 'tokenURI' },
    ],
  },
  fromBlock,
  toBlock: 'latest',
});
check(
  'BadgeDefined logs: 2 with names',
  definedLogs.length === 2 &&
    definedLogs
      .map((l) => l.args.name)
      .sort()
      .join() === 'First Steps,Token Holder',
  `(got ${definedLogs.length})`,
);

const attLogs = await publicClient.getLogs({
  address: d.questManager,
  event: {
    type: 'event',
    name: 'AttestationUsed',
    inputs: [
      { type: 'address', indexed: true, name: 'account' },
      { type: 'uint256', indexed: true, name: 'questId' },
      { type: 'uint256', indexed: false, name: 'nonce' },
      { type: 'address', indexed: true, name: 'signer' },
    ],
  },
  fromBlock,
  toBlock: 'latest',
});
check(
  'AttestationUsed logs: 2, one per threshold-2 signer (Phase 6)',
  attLogs.length === 2 &&
    attLogs
      .map((l) => l.args.signer.toLowerCase())
      .sort()
      .join() === [d.verifier.toLowerCase(), d.verifier2.toLowerCase()].sort().join(),
  `(got ${attLogs.length})`,
);

// 6. Badges + validator registry reads
const hasBadge1 = await publicClient.readContract({
  address: d.achievement,
  abi: ACHIEVEMENT_ABI,
  functionName: 'hasBadge',
  args: [d.alice, 1n],
});
check('hasBadge(alice, 1) is true', hasBadge1 === true);
const bobBadge1 = await publicClient.readContract({
  address: d.achievement,
  abi: ACHIEVEMENT_ABI,
  functionName: 'hasBadge',
  args: [d.bob, 1n],
});
check('hasBadge(bob, 1) is false', bobBadge1 === false);
const vInfo = await publicClient.readContract({
  address: d.questManager,
  abi: QUEST_MANAGER_ABI,
  functionName: 'validatorInfo',
  args: [d.validator],
});
check(
  'validatorInfo: approved, named TokenBalanceValidator',
  vInfo.approved === true && vInfo.name === 'TokenBalanceValidator',
);

// 7. Full attestation flow via viem (exactly what AttestationForm does):
// create a new Attested quest, sign as the verifier, recover + verify,
// submit as alice, confirm the receipt and the new points.
const deployerWallet = createWalletClient({
  account: privateKeyToAccount(DEPLOYER_KEY),
  chain: anvil,
  transport: http('http://127.0.0.1:8545'),
});
const now = Math.floor(Date.now() / 1000);
const createHash = await deployerWallet.writeContract({
  address: d.questManager,
  abi: QUEST_MANAGER_ABI,
  functionName: 'createQuest',
  // PHASE 6 (R-010): createQuest takes 11 params now — threshold 1 here.
  args: [
    'Daily Post',
    'Post daily (attested)',
    0,
    2,
    '0x0000000000000000000000000000000000000000',
    25n,
    0n,
    BigInt(now - 60),
    BigInt(now + 30 * 24 * 3600),
    0n,
    1,
  ],
});
await publicClient.waitForTransactionReceipt({ hash: createHash });
const count2 = await publicClient.readContract({
  address: d.questManager,
  abi: QUEST_MANAGER_ABI,
  functionName: 'questCount',
});
check('new Attested quest created (questCount 4)', eq(count2, 4), `(got ${count2})`);

const nonce = await publicClient.readContract({
  address: d.questManager,
  abi: QUEST_MANAGER_ABI,
  functionName: 'nonces',
  args: [d.alice],
});
check('nonces(alice) is 1 (one attestation used)', eq(nonce, 1), `(got ${nonce})`);

const deadline = BigInt(now + 3600);
const verifierAccount = privateKeyToAccount(VERIFIER_KEY);
const signature = await verifierAccount.signTypedData({
  domain: {
    name: 'AGENTHUB QuestManager',
    version: '1',
    chainId: 31337,
    verifyingContract: d.questManager,
  },
  types: {
    Attestation: [
      { name: 'account', type: 'address' },
      { name: 'questId', type: 'uint256' },
      { name: 'nonce', type: 'uint256' },
      { name: 'deadline', type: 'uint256' },
    ],
  },
  primaryType: 'Attestation',
  message: { account: d.alice, questId: 4n, nonce, deadline },
});
const recovered = await recoverTypedDataAddress({
  domain: {
    name: 'AGENTHUB QuestManager',
    version: '1',
    chainId: 31337,
    verifyingContract: d.questManager,
  },
  types: {
    Attestation: [
      { name: 'account', type: 'address' },
      { name: 'questId', type: 'uint256' },
      { name: 'nonce', type: 'uint256' },
      { name: 'deadline', type: 'uint256' },
    ],
  },
  primaryType: 'Attestation',
  message: { account: d.alice, questId: 4n, nonce, deadline },
  signature,
});
check(
  'viem attestation recovers the verifier',
  recovered.toLowerCase() === d.verifier.toLowerCase(),
  `(got ${recovered})`,
);

const aliceWallet = createWalletClient({
  account: privateKeyToAccount(ALICE_KEY),
  chain: anvil,
  transport: http('http://127.0.0.1:8545'),
});
const submitHash = await aliceWallet.writeContract({
  address: d.questManager,
  abi: QUEST_MANAGER_ABI,
  functionName: 'completeQuestWithAttestation',
  // PHASE 6 (R-010): signatures are a bytes[] array now (threshold 1
  // for this quest, so one signature suffices).
  args: [4n, deadline, [signature]],
});
const receipt = await publicClient.waitForTransactionReceipt({ hash: submitHash });
check('completeQuestWithAttestation receipt status is success', receipt.status === 'success');
const alicePoints2 = await publicClient.readContract({
  address: d.reputation,
  abi: REPUTATION_ABI,
  functionName: 'points',
  args: [d.alice],
});
check('points(alice) is now 275', eq(alicePoints2, 275), `(got ${alicePoints2})`);

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
