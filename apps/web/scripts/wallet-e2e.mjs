// Wallet E2E test (Phase F — final release remediation).
//
// SCOPE: the connected-wallet flows the unconnected smoke test
// (e2e-smoke.mjs) explicitly does NOT cover — wallet connection,
// Agent ID verification, on-chain quest listing, quest completion,
// the attestation form, and the dashboard points update — in a real
// headless Chromium against a live anvil chain.
//
// The "wallet" is a minimal injected EIP-1193 provider installed via
// page.addInitScript. It is NOT MetaMask/Binance Wallet: it bridges
// window.ethereum to a Node-side viem account holding a THROWAWAY
// ANVIL TEST KEY (bob, account #2 of the local test stack). It
// exercises the app's REAL wagmi injected() connector code path —
// connect, chain read, sendTransaction, receipt waiting — but a
// final manual check with a real wallet app on testnet is still
// required before mainnet (see FRONTEND_FINAL_ACCEPTANCE.md).
// NEVER point this script at a real key: WALLET_E2E_PRIVATE_KEY is
// a test key by design, and the script refuses to run against any
// chain other than local anvil (31337).
//
// Usage: run-wallet-e2e.sh builds the app against the local test
// stack, serves it, and runs this script. Env:
//   WALLET_E2E_BASE_URL (default http://127.0.0.1:3101)
//   WALLET_E2E_RPC_URL  (default http://127.0.0.1:8545)
//   WALLET_E2E_PRIVATE_KEY (default: bob's anvil test key)

import { chromium } from 'playwright';
import { createPublicClient, createWalletClient, http } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { anvil } from 'viem/chains';

const BASE = process.env.WALLET_E2E_BASE_URL ?? 'http://127.0.0.1:3101';
const RPC_URL = process.env.WALLET_E2E_RPC_URL ?? 'http://127.0.0.1:8545';
// Bob — anvil test account #2, holds a mock Agent ID in the local test
// stack, has completed NO quests at deploy time (alice completed all 3).
const BOB_KEY =
  process.env.WALLET_E2E_PRIVATE_KEY ??
  '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a';
const BOB = '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC';

const account = privateKeyToAccount(BOB_KEY);
if (account.address.toLowerCase() !== BOB.toLowerCase()) {
  console.error('WALLET_E2E_PRIVATE_KEY does not match the expected test account (bob)');
  process.exit(1);
}

const publicClient = createPublicClient({ chain: anvil, transport: http(RPC_URL) });
const walletClient = createWalletClient({ account, chain: anvil, transport: http(RPC_URL) });

// Safety: refuse to run against anything but local anvil.
const chainId = await publicClient.getChainId();
if (chainId !== 31337) {
  console.error(`refusing to run: RPC chain id is ${chainId}, expected local anvil (31337)`);
  process.exit(1);
}

let passed = 0;
let failed = 0;
const failures = [];
function check(name, ok, detail = '') {
  if (ok) {
    passed += 1;
    console.log(`  PASS ${name}`);
  } else {
    failed += 1;
    failures.push(name);
    console.log(`  FAIL ${name}${detail ? ` — ${detail}` : ''}`);
  }
}

const browser = await chromium.launch();
const page = await browser.newPage();
const pageErrors = [];
const consoleErrors = [];
page.on('pageerror', (err) => pageErrors.push(String(err)));
page.on('console', (msg) => {
  if (msg.type() === 'error') consoleErrors.push(msg.text());
});

// --- Injected EIP-1193 provider bridge (Node side) ---
// Signing methods go through the viem test account; everything else is
// a raw JSON-RPC forward to anvil.
await page.exposeFunction('__e2e_rpc', async ({ method, params }) => {
  switch (method) {
    case 'eth_requestAccounts':
    case 'eth_accounts':
      return [BOB];
    case 'eth_chainId':
      return '0x7a69';
    case 'net_version':
      return '31337';
    case 'wallet_switchEthereumChain': {
      const target = params?.[0]?.chainId;
      if (target === '0x7a69') return null;
      const err = new Error(`wallet: chain ${target} not available in test wallet`);
      err.code = 4902;
      throw err;
    }
    case 'wallet_addEthereumChain':
      return null;
    case 'eth_sendTransaction': {
      const tx = params[0];
      const hash = await walletClient.sendTransaction({
        to: tx.to,
        data: tx.data,
        value: tx.value ? BigInt(tx.value) : 0n,
      });
      return hash;
    }
    case 'personal_sign': {
      const message = params[0];
      const hex = message.startsWith('0x')
        ? message
        : `0x${Buffer.from(message, 'utf8').toString('hex')}`;
      return account.signMessage({ message: { raw: hex } });
    }
    case 'eth_signTypedData_v4': {
      const typedData = JSON.parse(params[1]);
      return account.signTypedData({
        domain: typedData.domain,
        types: typedData.types,
        primaryType: typedData.primaryType,
        message: typedData.message,
      });
    }
    default: {
      const res = await fetch(RPC_URL, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params: params ?? [] }),
      });
      const json = await res.json();
      if (json.error) {
        const err = new Error(json.error.message ?? 'RPC error');
        err.code = json.error.code;
        throw err;
      }
      return json.result;
    }
  }
});

// --- Injected provider stub (browser side, before page scripts) ---
await page.addInitScript(() => {
  const listeners = {};
  window.ethereum = {
    isMetaMask: true,
    request: async (args) => window.__e2e_rpc(args),
    on: (event, cb) => {
      listeners[event] = listeners[event] ?? [];
      listeners[event].push(cb);
    },
    removeListener: (event, cb) => {
      listeners[event] = (listeners[event] ?? []).filter((f) => f !== cb);
    },
    removeAllListeners: (event) => {
      if (event) delete listeners[event];
    },
  };
});

// --- 1. Home + connect ---
await page.goto(`${BASE}/`, { waitUntil: 'networkidle' });
check('home loads', (await page.locator('h1').count()) >= 1);
await page.getByRole('button', { name: 'Connect Binance Wallet' }).click();
await page.waitForTimeout(1500);
const navText = await page.textContent('body');
check('wallet connected — truncated bob address shown', navText?.includes('0x3C44…93BC') ?? false);

// --- 2. Profile: Agent ID verified on-chain ---
await page.goto(`${BASE}/profile`, { waitUntil: 'networkidle' });
await page.waitForTimeout(2000);
const profileText = await page.textContent('body');
check(
  'Agent ID verified for bob (mock ID in test stack)',
  profileText?.includes('Agent ID verified — you hold an Agent ID.') ?? false,
);

// --- 3. Quests: live on-chain list, no preview label ---
await page.goto(`${BASE}/quests`, { waitUntil: 'networkidle' });
await page.waitForTimeout(2000);
const questsText = await page.textContent('body');
check(
  'quests page shows the live label',
  questsText?.includes('Live quests from QuestManager') ?? false,
);
check(
  'quests page does NOT show the undeployed preview label',
  !(questsText?.includes('Launch catalogue preview') ?? true),
);
for (const name of ['First Steps', 'Hold 100 Tokens', 'Post on X']) {
  check(`on-chain quest listed: ${name}`, questsText?.includes(name) ?? false);
}

// --- 4. Complete q1 "First Steps" (CheckIn) as bob ---
const completeBtn = page.getByRole('button', { name: 'Complete quest' }).first();
check('q1 Complete button is enabled for bob', await completeBtn.isEnabled());
await completeBtn.click();
await page.waitForTimeout(6000);
const afterComplete = await page.textContent('body');
check('q1 shows Completed after tx confirms', afterComplete?.includes('Completed ✓') ?? false);

// Verify on-chain (independent of the UI): hasCompleted + points.
const deployment = JSON.parse(
  (await import('node:fs')).readFileSync(
    new URL('../.anvil-deployment.json', import.meta.url),
    'utf8',
  ),
);
const QM_ABI = [
  {
    type: 'function',
    name: 'hasCompleted',
    inputs: [
      { name: 'account', type: 'address' },
      { name: 'questId', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'view',
  },
];
const REP_ABI = [
  {
    type: 'function',
    name: 'points',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
];
const completedOnChain = await publicClient.readContract({
  address: deployment.questManager,
  abi: QM_ABI,
  functionName: 'hasCompleted',
  args: [BOB, 1n],
});
const pointsOnChain = await publicClient.readContract({
  address: deployment.reputation,
  abi: REP_ABI,
  functionName: 'points',
  args: [BOB],
});
check('on-chain: hasCompleted(bob, q1) is true', completedOnChain === true);
check('on-chain: points(bob) is 50 after q1', pointsOnChain === 50n, `got ${pointsOnChain}`);

// --- 5. Dashboard shows the new points ---
await page.goto(`${BASE}/dashboard`, { waitUntil: 'networkidle' });
await page.waitForTimeout(2000);
const dashText = await page.textContent('body');
check('dashboard shows 50 pts for bob', dashText?.includes('50 pts') ?? false);

// --- 6. Full attestation flow for q3 "Post on X" (Attested, threshold 2) ---
// PHASE 6 (R-010): BOTH test-stack verifiers sign the SAME digest (same
// account, quest, nonce, deadline), then drive the real form in the
// browser: toggle -> paste 2 signatures -> verify -> submit ->
// confirmed on-chain.
const VERIFIER_KEY = '0x0000000000000000000000000000000000000000000000000000000000a11ce5';
const VERIFIER2_KEY = '0x0000000000000000000000000000000000000000000000000000000000a11ce6';
const verifierAccount = privateKeyToAccount(VERIFIER_KEY);
const verifier2Account = privateKeyToAccount(VERIFIER2_KEY);
const NONCE_ABI = [
  {
    type: 'function',
    name: 'nonces',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
];
const bobNonce = await publicClient.readContract({
  address: deployment.questManager,
  abi: NONCE_ABI,
  functionName: 'nonces',
  args: [BOB],
});
const attDeadline = Math.floor(Date.now() / 1000) + 3600;
const attestationTypedData = {
  domain: {
    name: 'AGENTHUB QuestManager',
    version: '1',
    chainId: 31337,
    verifyingContract: deployment.questManager,
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
  message: { account: BOB, questId: 3n, nonce: bobNonce, deadline: BigInt(attDeadline) },
};
const attSignature = await verifierAccount.signTypedData(attestationTypedData);
const attSignature2 = await verifier2Account.signTypedData(attestationTypedData);
check(
  'threshold-2 pair signed for bob/q3 in Node (same digest, 2 verifiers)',
  attSignature.length === 132 && attSignature2.length === 132 && attSignature !== attSignature2,
  `nonce ${bobNonce}`,
);
await page.goto(`${BASE}/quests`, { waitUntil: 'networkidle' });
await page.waitForTimeout(2000);
await page.getByRole('button', { name: 'Submit attestation' }).first().click();
await page.waitForTimeout(500);
const formText = await page.textContent('body');
check(
  'attestation form appears after toggling',
  formText?.includes('paste the signature your verifier gave you') ?? false,
);
check(
  'form shows the threshold-2 requirement',
  formText?.includes('requires 2 verifier signatures') ?? false,
);
await page.getByLabel('Signature 1 (65-byte 0x hex)').fill(attSignature);
await page.getByLabel('Signature 2 (65-byte 0x hex)').fill(attSignature2);
await page.getByLabel('Deadline (Unix timestamp, seconds)').fill(String(attDeadline));
await page.getByRole('button', { name: 'Verify attestation' }).click();
await page
  .getByText('(verified verifier ✓)')
  .first()
  .waitFor({ timeout: 15000 })
  .catch(() => {});
await page.waitForTimeout(1500);
const verifiedCount = await page.getByText('(verified verifier ✓)').count();
check(
  'form verifies BOTH attestation signers (each holds VERIFIER_ROLE)',
  verifiedCount === 2,
  `got ${verifiedCount}`,
);
await page.getByRole('button', { name: 'Submit attestation' }).click();
await page.waitForTimeout(6000);
const afterAtt = await page.textContent('body');
check('q3 shows Completed after attested tx confirms', afterAtt?.includes('Completed ✓') ?? false);
const q3OnChain = await publicClient.readContract({
  address: deployment.questManager,
  abi: QM_ABI,
  functionName: 'hasCompleted',
  args: [BOB, 3n],
});
const pointsAfterQ3 = await publicClient.readContract({
  address: deployment.reputation,
  abi: REP_ABI,
  functionName: 'points',
  args: [BOB],
});
check('on-chain: hasCompleted(bob, q3) is true', q3OnChain === true);
check('on-chain: points(bob) is 150 after q3', pointsAfterQ3 === 150n, `got ${pointsAfterQ3}`);

// --- 7. OnChain quest bob cannot pass: no false success ---
// --- 7. OnChain quest bob cannot pass: no false success ---
// Bob holds 0 TEST tokens, so q2's validator rejects him. The UI must
// not claim success; on-chain state must stay uncompleted.
const q2Btn = page.getByRole('button', { name: 'Complete (on-chain check)' }).first();
if ((await q2Btn.count()) === 1 && (await q2Btn.isEnabled())) {
  await q2Btn.click();
  await page.waitForTimeout(5000);
  // q2's own button must still read 'Complete (on-chain check)' — it
  // must not flip to 'Completed ✓'. (A global Completed count is
  // meaningless here: q3's form button legitimately still shows
  // 'Completed ✓' in this same page session.)
  const q2StillPending = await page
    .getByRole('button', { name: 'Complete (on-chain check)' })
    .count();
  check(
    "q2 button still reads 'Complete (on-chain check)'",
    q2StillPending === 1,
    `got ${q2StillPending}`,
  );
  const q2OnChain = await publicClient.readContract({
    address: deployment.questManager,
    abi: QM_ABI,
    functionName: 'hasCompleted',
    args: [BOB, 2n],
  });
  check('on-chain: hasCompleted(bob, q2) stays false', q2OnChain === false);
} else {
  check(
    'q2 Complete button present and enabled for the negative test',
    false,
    'button missing/disabled',
  );
}

// --- 8. Mobile viewport: no horizontal overflow ---
await page.setViewportSize({ width: 375, height: 667 });
await page.goto(`${BASE}/quests`, { waitUntil: 'networkidle' });
await page.waitForTimeout(1500);
const overflow = await page.evaluate(
  () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
);
check('mobile (375px): no horizontal overflow on /quests', overflow <= 1, `overflow ${overflow}px`);
const connectVisible = await page
  .getByRole('button', { name: /0x3C44…93BC|Connect Binance Wallet/ })
  .first()
  .isVisible()
  .catch(() => false);
check('mobile: wallet button visible', connectVisible);

// --- 9. No JS errors anywhere ---
check('no page errors', pageErrors.length === 0, pageErrors[0] ?? '');
check('no console errors', consoleErrors.length === 0, consoleErrors[0] ?? '');

await browser.close();
console.log(`\nWallet E2E: ${passed} passed, ${failed} failed`);
if (failed > 0) {
  console.log(`Failures: ${failures.join(', ')}`);
  process.exit(1);
}
console.log('ALL WALLET E2E CHECKS PASSED');
