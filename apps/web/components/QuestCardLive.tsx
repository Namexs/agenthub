'use client';

import { useState } from 'react';
import { QuestType, ValidationKind } from '@agenthub/shared';
import { GlassCard } from './GlassCard';
import { AttestationForm } from './AttestationForm';
import { useAgentId } from '@/hooks/useAgentId';
import { useChainGuard } from '@/hooks/useChainGuard';
import { useCompleteQuest } from '@/hooks/useCompleteQuest';
import type { QuestWithState } from '@/hooks/useQuests';
import { questEligibility, validationKindLabel } from '@/lib/quests';
import { formatAddress } from '@/lib/utils';
import { env } from '@/lib/env';
import { explorerTxUrl } from '@/lib/events';

const TYPE_LABEL: Record<QuestType, string> = {
  [QuestType.DailyCheckIn]: 'Daily',
  [QuestType.OneTime]: 'One-time',
  [QuestType.Weekly]: 'Weekly',
  [QuestType.Community]: 'Community',
};

// Live on-chain quest card (Phase 7). Shows the quest's real state,
// the honest validation-kind label, eligibility, and the completion
// action — a plain Complete button for CheckIn/OnChain quests, the
// attestation form for Attested quests. Transaction status is shown
// through the full lifecycle; a submitted tx is NOT a completion until
// the receipt confirms it.
export function QuestCardLive({ quest }: { quest: QuestWithState }) {
  const { isHolder, isConnected } = useAgentId();
  const { isSupported } = useChainGuard();
  const { complete, hash, isPending, isConfirming, isSuccess, isFailed, error } =
    useCompleteQuest();
  const [showAttestation, setShowAttestation] = useState(false);

  const nowSeconds = Math.floor(Date.now() / 1000);
  const eligibility = questEligibility(quest, quest.state, nowSeconds, isHolder);

  const windowLabel =
    quest.startTime > 0
      ? `${new Date(quest.startTime * 1000).toLocaleDateString()} – ${new Date(
          quest.endTime * 1000,
        ).toLocaleDateString()}`
      : 'Always open';

  return (
    <GlassCard className="flex flex-col gap-3 p-5">
      <div className="flex items-center justify-between">
        <span className="rounded-pill border border-electric-500/50 bg-electric-600/10 px-3 py-1 text-xs font-medium text-electric-300">
          {TYPE_LABEL[quest.questType]}
        </span>
        <span className="text-sm font-semibold text-agent-300">+{quest.rewardPoints} pts</span>
      </div>
      <h3 className="text-lg font-semibold text-ink-100">{quest.title}</h3>
      <p className="flex-1 text-sm leading-relaxed text-ink-400">{quest.description}</p>
      <p className="text-xs text-ink-500">{validationKindLabel(quest.validationKind)}</p>
      <div className="flex items-center justify-between text-xs text-ink-500">
        <span>{quest.badgeId > 0 ? `Badge #${quest.badgeId} on completion` : 'No badge'}</span>
        <span>
          {quest.maxCompletions > 0
            ? `${quest.completions}/${quest.maxCompletions} completed`
            : `${quest.completions} completed`}
        </span>
      </div>
      <p className="text-xs text-ink-500">{windowLabel}</p>

      {!isConnected ? (
        <p className="text-xs text-ink-400">Connect your wallet to complete this quest.</p>
      ) : eligibility.needsAttestation ? (
        <>
          <button
            type="button"
            onClick={() => setShowAttestation((s) => !s)}
            className="rounded-pill border border-agent-400/50 bg-agent-500/10 px-4 py-2 text-sm font-medium text-agent-300 transition hover:bg-agent-500/20"
          >
            {showAttestation ? 'Hide attestation form' : 'Submit attestation'}
          </button>
          {showAttestation && <AttestationForm questId={quest.id} questTitle={quest.title} />}
        </>
      ) : (
        <>
          <button
            type="button"
            onClick={() => complete(quest.id)}
            disabled={
              !eligibility.canComplete || !isSupported || isPending || isConfirming || isSuccess
            }
            className="rounded-pill bg-gradient-to-r from-agent-500 to-electric-600 px-4 py-2 text-sm font-semibold text-white transition hover:opacity-90 disabled:opacity-50"
            title={eligibility.reason ?? undefined}
          >
            {isPending
              ? 'Confirm in wallet…'
              : isConfirming
                ? 'Confirming…'
                : isSuccess
                  ? 'Completed ✓'
                  : eligibility.canComplete
                    ? quest.validationKind === ValidationKind.OnChain
                      ? 'Complete (on-chain check)'
                      : 'Complete quest'
                    : (eligibility.reason ?? 'Unavailable')}
          </button>
          {hash && (
            <p className="text-xs text-ink-400">
              Tx:{' '}
              {explorerTxUrl(env.NEXT_PUBLIC_CHAIN_ID, hash) ? (
                <a
                  href={explorerTxUrl(env.NEXT_PUBLIC_CHAIN_ID, hash)}
                  target="_blank"
                  rel="noreferrer"
                  className="font-mono text-electric-300 underline"
                >
                  {formatAddress(hash)}
                </a>
              ) : (
                <span className="font-mono">{formatAddress(hash)}</span>
              )}{' '}
              {isSuccess
                ? '— confirmed on-chain ✓'
                : isConfirming
                  ? '— waiting for confirmation…'
                  : ''}
            </p>
          )}
          {isFailed && error && <p className="text-xs text-red-300">{error}</p>}
        </>
      )}
    </GlassCard>
  );
}
