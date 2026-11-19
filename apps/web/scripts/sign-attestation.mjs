// Local verifier attestation signer (Phase E — final release remediation).
//
// WHAT THIS IS: a minimal command-line tool for an AGENTHUB verifier to
// sign one EIP-712 attestation on their OWN machine. The verifier key is
// read from the VERIFIER_PRIVATE_KEY environment variable and NEVER leaves
// this process: it is not sent to any server, not written to disk, and
// never printed. The script only READS from the chain (nonce, chain id,
// VERIFIER_ROLE check) and signs locally.
//
// WHAT THIS IS NOT: a backend signing service. There is no server, no
// hosted key, and no API. For testnet staging (one verifier, manual
// issuance) this local tool is the whole signing path. A production
// service verifier MUST use a hardware wallet or HSM instead of a
// plaintext env key — see docs/VERIFIER_ROLE_SOP.md §1.
//
// TRUST ASSUMPTIONS (documented, not hidden):
// - Whoever runs this script holds the verifier key for this run. A
//   compromised machine = a compromised verifier key; the mitigation is
//   the SOP (dedicated key, no funds on it, pause + revoke on suspicion).
// - The script trusts the --rpc-url endpoint for reads (nonce, chain id,
//   role check). A lying RPC could make the script sign over a stale
//   nonce (harmless: the attestation would simply fail on-chain) or a
//   wrong chain id (the signature would be invalid on the real chain).
//   Always use a trusted RPC endpoint, and verify the printed chain id
//   matches the deployment before delivering the signature.
// - The signature is delivered to the user out-of-band; anyone holding
//   it can submit it — but only FOR the bound account, quest, and
//   deadline, and only once (nonce). A leaked signature cannot be
//   redirected to another user or quest.
//
// Usage (from the repo root):
//   VERIFIER_PRIVATE_KEY=0x... node apps/web/scripts/sign-attestation.mjs \
//     --rpc-url https://data-seed-prebsc-1-s1.bnbchain.org:8545 \
//     --quest-manager 0x... \
//     --account 0x... \
//     --quest-id 3 \
//     --valid-for-seconds 3600
//
// Or pass an absolute deadline instead of --valid-for-seconds:
//     --deadline 1797000000
//
// The script prints the account, quest id, nonce, deadline, and the
// signature — exactly what the user pastes into the attestation form.
// It never prints the private key.
//
// Exit codes: 0 = signed OK; 1 = usage/validation error; 2 = the signer
// does not hold VERIFIER_ROLE on-chain (refuses to sign); 3 = RPC error.

import { createPublicClient, http, recoverTypedDataAddress } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';

const DOMAIN_NAME = 'AGENTHUB QuestManager';
const DOMAIN_VERSION = '1';
const MAX_ATTESTATION_LIFETIME_SECONDS = 7 * 24 * 60 * 60;

const ATTESTATION_TYPES = {
  Attestation: [
    { name: 'account', type: 'address' },
    { name: 'questId', type: 'uint256' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' },
  ],
};

// Minimal ABI: only the reads this script needs.
const QUEST_MANAGER_READ_ABI = [
  {
    type: 'function',
    name: 'nonces',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'hasRole',
    inputs: [
      { name: 'role', type: 'bytes32' },
      { name: 'account', type: 'address' },
    ],
    outputs: [{ name: '', type: 'bool' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'VERIFIER_ROLE',
    inputs: [],
    outputs: [{ name: '', type: 'bytes32' }],
    stateMutability: 'view',
  },
];

function fail(message, code = 1) {
  console.error(`sign-attestation: ERROR: ${message}`);
  process.exit(code);
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (!arg.startsWith('--')) fail(`unexpected argument: ${arg}`);
    const key = arg.slice(2);
    const value = argv[i + 1];
    if (value === undefined || value.startsWith('--')) fail(`missing value for --${key}`);
    args[key] = value;
    i++;
  }
  return args;
}

const args = parseArgs(process.argv.slice(2));
for (const required of ['rpc-url', 'quest-manager', 'account', 'quest-id']) {
  if (!args[required]) fail(`missing required argument --${required}`);
}
if (!args.deadline && !args['valid-for-seconds']) {
  fail('pass either --deadline <unix seconds> or --valid-for-seconds <seconds>');
}
if (args.deadline && args['valid-for-seconds']) {
  fail('pass only one of --deadline and --valid-for-seconds');
}

const ADDRESS_RE = /^0x[0-9a-fA-F]{40}$/;
if (!ADDRESS_RE.test(args['quest-manager'])) fail('--quest-manager must be a 0x address');
if (!ADDRESS_RE.test(args.account)) fail('--account must be a 0x address');
if (!/^\d+$/.test(args['quest-id'])) fail('--quest-id must be a non-negative integer');

const key = process.env.VERIFIER_PRIVATE_KEY;
if (!key) {
  fail(
    'VERIFIER_PRIVATE_KEY is not set. Export it in this shell only ' +
      '(never commit it, never pass it as a CLI argument — CLI args leak into shell history).',
  );
}
if (!/^0x[0-9a-fA-F]{64}$/.test(key)) {
  fail('VERIFIER_PRIVATE_KEY must be a 0x-prefixed 32-byte hex key');
}
const signerAccount = privateKeyToAccount(key);

const now = Math.floor(Date.now() / 1000);
let deadline;
if (args.deadline) {
  if (!/^\d+$/.test(args.deadline)) fail('--deadline must be a Unix timestamp in seconds');
  deadline = Number(args.deadline);
} else {
  if (!/^\d+$/.test(args['valid-for-seconds']))
    fail('--valid-for-seconds must be a number of seconds');
  deadline = now + Number(args['valid-for-seconds']);
}
if (deadline <= now) fail(`deadline ${deadline} is not in the future (now ${now})`);
if (deadline > now + MAX_ATTESTATION_LIFETIME_SECONDS) {
  fail('deadline is more than 7 days out — the contract will reject it (MAX_ATTESTATION_LIFETIME)');
}

const publicClient = createPublicClient({ transport: http(args['rpc-url']) });

let chainId;
let nonce;
let verifierRole;
try {
  chainId = await publicClient.getChainId();
  nonce = await publicClient.readContract({
    address: args['quest-manager'],
    abi: QUEST_MANAGER_READ_ABI,
    functionName: 'nonces',
    args: [args.account],
  });
  verifierRole = await publicClient.readContract({
    address: args['quest-manager'],
    abi: QUEST_MANAGER_READ_ABI,
    functionName: 'VERIFIER_ROLE',
  });
} catch (err) {
  fail(
    `RPC read failed (${args['rpc-url']}): ${err instanceof Error ? err.message : String(err)}`,
    3,
  );
}

let isVerifier;
try {
  isVerifier = await publicClient.readContract({
    address: args['quest-manager'],
    abi: QUEST_MANAGER_READ_ABI,
    functionName: 'hasRole',
    args: [verifierRole, signerAccount.address],
  });
} catch (err) {
  fail(`VERIFIER_ROLE check failed: ${err instanceof Error ? err.message : String(err)}`, 3);
}
if (!isVerifier) {
  fail(
    `signer ${signerAccount.address} does NOT hold VERIFIER_ROLE on QuestManager ` +
      `${args['quest-manager']} (chain ${chainId}). Refusing to sign — ` +
      'an attestation from this key would be rejected on-chain. ' +
      'Check the key, the contract address, and the RPC endpoint.',
    2,
  );
}

const domain = {
  name: DOMAIN_NAME,
  version: DOMAIN_VERSION,
  chainId,
  verifyingContract: args['quest-manager'],
};
const message = {
  account: args.account,
  questId: BigInt(args['quest-id']),
  nonce,
  deadline: BigInt(deadline),
};

const signature = await signerAccount.signTypedData({
  domain,
  types: ATTESTATION_TYPES,
  primaryType: 'Attestation',
  message,
});

// Self-check: the signature must recover to this signer.
const recovered = await recoverTypedDataAddress({
  domain,
  types: ATTESTATION_TYPES,
  primaryType: 'Attestation',
  message,
  signature,
});
if (recovered.toLowerCase() !== signerAccount.address.toLowerCase()) {
  fail(`self-check failed: signature recovers to ${recovered}, expected ${signerAccount.address}`);
}

console.log(
  'Attestation signed. Deliver these values to the user (paste into the attestation form):',
);
console.log(`  chainId:   ${chainId}`);
console.log(`  questManager: ${args['quest-manager']}`);
console.log(`  account:   ${args.account}`);
console.log(`  questId:   ${args['quest-id']}`);
console.log(`  nonce:     ${nonce}`);
console.log(`  deadline:  ${deadline} (${new Date(deadline * 1000).toISOString()})`);
console.log(`  signer:    ${signerAccount.address} (VERIFIER_ROLE confirmed on-chain)`);
console.log(`  signature: ${signature}`);
