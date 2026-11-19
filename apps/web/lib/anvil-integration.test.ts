import { describe, it, expect, beforeAll } from 'vitest';
import { readFileSync } from 'node:fs';
import { createPublicClient, createWalletClient, http } from 'viem';
import { anvil } from 'viem/chains';
import { privateKeyToAccount } from 'viem/accounts';
import { QUEST_MANAGER_ABI } from './abis/QuestManager';
import { REPUTATION_ABI } from './abis/Reputation';
import { mapQuest, questEligibility, type RawQuest } from './quests';
import { checkAttestations } from './attestation';
import { aggregateLeaderboard, buildTxHistory, computeLevel, EVENT_SIGNATURES } from './events';
import { parseAbiItem } from 'viem';

// Frontend integration test against a LIVE local deployment (Phase 7).
// Skipped unless ANVIL_DEPLOYMENT points at the deployment JSON written
// by DeployLocalTestStack.s.sol (run via run-anvil-integration.sh).
// Unlike the forge unit tests, this exercises the REAL frontend lib
// functions (mapQuest, questEligibility, checkAttestation,
// aggregateLeaderboard, buildTxHistory) against real on-chain data.
//
// The keys below are PUBLIC anvil/test keys — local anvil only.

const DEPLOYMENT_PATH = process.env.ANVIL_DEPLOYMENT;
const enabled = Boolean(DEPLOYMENT_PATH);

interface Deployment {
  chainId: number;
  deployBlock: number;
  agentId: `0x${string}`;
  agentGate: `0x${string}`;
  questManager: `0x${string}`;
  reputation: `0x${string}`;
  achievement: `0x${string}`;
  validator: `0x${string}`;
  token: `0x${string}`;
  deployer: `0x${string}`;
  alice: `0x${string}`;
  bob: `0x${string}`;
  verifier: `0x${string}`;
  verifier2: `0x${string}`;
}

const BOB_KEY = '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a';
const VERIFIER_KEY = '0x0000000000000000000000000000000000000000000000000000000000a11ce5';
// PHASE 6 (R-010): second verifier — q3 is a threshold-2 quest now.
const VERIFIER2_KEY = '0x0000000000000000000000000000000000000000000000000000000000a11ce6';

describe.skipIf(!enabled)('anvil integration (frontend lib vs live chain)', () => {
  let d: Deployment;
  let client: ReturnType<typeof createPublicClient>;

  beforeAll(() => {
    d = JSON.parse(readFileSync(DEPLOYMENT_PATH as string, 'utf8')) as Deployment;
    client = createPublicClient({ chain: anvil, transport: http('http://127.0.0.1:8545') });
  });

  it('mapQuest maps live getQuest data to the shared Quest type', async () => {
    const raw = (await client.readContract({
      address: d.questManager,
      abi: QUEST_MANAGER_ABI,
      functionName: 'getQuest',
      args: [1n],
    })) as unknown as RawQuest;
    const quest = mapQuest(raw);
    expect(quest.id).toBe(1);
    expect(quest.title).toBe('First Steps');
    expect(quest.validationKind).toBe('check-in');
    expect(quest.rewardPoints).toBe(50);
    expect(quest.badgeId).toBe(1);
    expect(quest.completions).toBe(1);
    expect(quest.active).toBe(true);
    expect(quest.attestationThreshold).toBe(1);
  });

  it('mapQuest maps the threshold-2 attested quest (Phase 6)', async () => {
    const raw = (await client.readContract({
      address: d.questManager,
      abi: QUEST_MANAGER_ABI,
      functionName: 'getQuest',
      args: [3n],
    })) as unknown as RawQuest;
    const quest = mapQuest(raw);
    expect(quest.title).toBe('Post on X');
    expect(quest.validationKind).toBe('attested');
    expect(quest.attestationThreshold).toBe(2);
  });

  it('questEligibility matches on-chain state for alice (done) and bob (open)', async () => {
    const raw = (await client.readContract({
      address: d.questManager,
      abi: QUEST_MANAGER_ABI,
      functionName: 'getQuest',
      args: [1n],
    })) as unknown as RawQuest;
    const quest = mapQuest(raw);
    const now = Math.floor(Date.now() / 1000);
    expect(
      questEligibility(quest, { completed: true, nextCompletionAt: 0 }, now, true),
    ).toMatchObject({ canComplete: false, reason: 'Already completed' });
    expect(
      questEligibility(quest, { completed: false, nextCompletionAt: 0 }, now, true),
    ).toMatchObject({ canComplete: true, reason: null });
    expect(
      questEligibility(quest, { completed: false, nextCompletionAt: 0 }, now, false),
    ).toMatchObject({ canComplete: false, reason: 'Requires an Agent ID' });
  });

  it('checkAttestations verifies a real threshold-2 pair, and the submission lands', async () => {
    // Bob has not completed quest 3 (Attested, threshold 2); his nonce is 0.
    const nonce = (await client.readContract({
      address: d.questManager,
      abi: QUEST_MANAGER_ABI,
      functionName: 'nonces',
      args: [d.bob],
    })) as bigint;
    expect(nonce).toBe(0n);

    const deadline = Math.floor(Date.now() / 1000) + 3600;
    // PHASE 6 (R-010): BOTH verifiers sign the SAME digest (same
    // account, quest, nonce, deadline) — exactly what the form collects.
    const domain = {
      name: 'AGENTHUB QuestManager',
      version: '1',
      chainId: 31337,
      verifyingContract: d.questManager,
    } as const;
    const types = {
      Attestation: [
        { name: 'account', type: 'address' },
        { name: 'questId', type: 'uint256' },
        { name: 'nonce', type: 'uint256' },
        { name: 'deadline', type: 'uint256' },
      ],
    } as const;
    const message = { account: d.bob, questId: 3n, nonce, deadline: BigInt(deadline) };
    const signature1 = await privateKeyToAccount(VERIFIER_KEY).signTypedData({
      domain,
      types,
      primaryType: 'Attestation',
      message,
    });
    const signature2 = await privateKeyToAccount(VERIFIER2_KEY).signTypedData({
      domain,
      types,
      primaryType: 'Attestation',
      message,
    });

    // The REAL frontend check (lib/attestation.ts) against live data.
    const result = await checkAttestations(
      {
        account: d.bob,
        questId: 3,
        nonce: Number(nonce),
        deadline,
        signatures: [signature1, signature2],
      },
      2,
      31337,
      d.questManager,
      Math.floor(Date.now() / 1000),
    );
    expect(result.valid).toBe(true);
    expect(result.signers.map((s) => s.toLowerCase()).sort()).toEqual(
      [d.verifier.toLowerCase(), d.verifier2.toLowerCase()].sort(),
    );
    expect(result.errors).toEqual([]);

    // And the submission the AttestationForm performs.
    const bobWallet = createWalletClient({
      account: privateKeyToAccount(BOB_KEY),
      chain: anvil,
      transport: http('http://127.0.0.1:8545'),
    });
    const hash = await bobWallet.writeContract({
      address: d.questManager,
      abi: QUEST_MANAGER_ABI,
      functionName: 'completeQuestWithAttestation',
      args: [3n, BigInt(deadline), [signature1, signature2]],
    });
    const receipt = await client.waitForTransactionReceipt({ hash });
    expect(receipt.status).toBe('success');
    const points = (await client.readContract({
      address: d.reputation,
      abi: REPUTATION_ABI,
      functionName: 'points',
      args: [d.bob],
    })) as bigint;
    expect(points).toBe(100n);
  });

  it('aggregateLeaderboard + buildTxHistory work on live logs', async () => {
    const fromBlock = BigInt(d.deployBlock);
    const completedLogs = await client.getLogs({
      address: d.questManager,
      event: parseAbiItem(EVENT_SIGNATURES.questCompleted),
      fromBlock,
      toBlock: 'latest',
    });
    const pointsLogs = await client.getLogs({
      address: d.reputation,
      event: parseAbiItem(EVENT_SIGNATURES.pointsAdded),
      fromBlock,
      toBlock: 'latest',
    });
    const attLogs = await client.getLogs({
      address: d.questManager,
      event: parseAbiItem(EVENT_SIGNATURES.attestationUsed),
      fromBlock,
      toBlock: 'latest',
    });
    const toDecoded = (logs: unknown[]) =>
      (
        logs as {
          transactionHash: `0x${string}`;
          blockNumber: bigint;
          logIndex: number;
          args: Record<string, unknown>;
        }[]
      ).map((l) => ({
        transactionHash: l.transactionHash,
        blockNumber: Number(l.blockNumber),
        logIndex: l.logIndex,
        args: l.args,
      }));

    const board = aggregateLeaderboard(toDecoded(completedLogs), toDecoded(pointsLogs));
    expect(board.length).toBeGreaterThanOrEqual(2);
    // Alice completed 4 quests by now (3 in the deploy script + 1 in the
    // node checks); bob completed 1 in the previous test.
    const alice = board.find((e) => e.address.toLowerCase() === d.alice.toLowerCase());
    const bob = board.find((e) => e.address.toLowerCase() === d.bob.toLowerCase());
    expect(alice).toBeDefined();
    expect(alice?.points).toBe(275);
    expect(alice?.level).toBe(computeLevel(275));
    // The aggregated level must match the CONTRACT's level (1-based) —
    // the anvil run caught a 0-based computeLevel here.
    const onChainLevel = (await client.readContract({
      address: d.reputation,
      abi: REPUTATION_ABI,
      functionName: 'level',
      args: [d.alice],
    })) as number;
    expect(alice?.level).toBe(Number(onChainLevel));
    expect(alice?.questsCompleted).toBe(4);
    expect(alice?.rank).toBe(1);
    expect(bob?.points).toBe(100);
    expect(bob?.questsCompleted).toBe(1);

    const history = buildTxHistory({
      questCompleted: toDecoded(completedLogs),
      pointsAdded: toDecoded(pointsLogs),
      badgeIssued: [],
      attestationUsed: toDecoded(attLogs),
    });
    const attEntries = history.filter((e) => e.kind === 'attestation');
    expect(attEntries.length).toBeGreaterThanOrEqual(2);
    // PHASE 6 (R-010): threshold-2 completions emit one AttestationUsed
    // event PER signer — both verifiers appear in the history.
    const verifiers = [d.verifier.toLowerCase(), d.verifier2.toLowerCase()];
    expect(attEntries.every((e) => verifiers.includes(e.signer?.toLowerCase() ?? ''))).toBe(true);
    expect(new Set(attEntries.map((e) => e.signer?.toLowerCase())).size).toBe(2);
    // Newest first.
    for (let i = 1; i < history.length; i++) {
      const prev = history[i - 1];
      const cur = history[i];
      if (prev === undefined || cur === undefined) throw new Error('unreachable');
      expect(
        prev.blockNumber > cur.blockNumber ||
          (prev.blockNumber === cur.blockNumber && prev.logIndex >= cur.logIndex),
      ).toBe(true);
    }
  });
});
