import type { TxHistoryEntry } from '@agenthub/shared';
import { formatAddress } from '@/lib/utils';
import { env } from '@/lib/env';
import { explorerTxUrl } from '@/lib/events';

// Shared activity-history list (Phase 7). One row per on-chain event:
// quest completion, points award, badge issuance, attestation use. Every
// row links to BscScan (except on local Anvil, where there is no
// explorer). Used by /history (full list) and /dashboard (recent 5).
export function TxHistoryList({ entries }: { entries: TxHistoryEntry[] }) {
  if (entries.length === 0) {
    return (
      <p className="py-6 text-center text-sm text-ink-400">
        No transactions yet — history appears after your first on-chain quest completion.
      </p>
    );
  }
  return (
    <ul className="divide-y divide-navy-700/40">
      {entries.map((entry) => (
        <li
          key={`${entry.hash}:${entry.logIndex}`}
          className="flex flex-wrap items-center justify-between gap-2 py-3"
        >
          <div className="text-sm">
            <p className="font-medium text-ink-100">
              {entry.kind === 'quest' && `Completed quest #${entry.questId}`}
              {entry.kind === 'points' &&
                `Earned ${entry.points ?? 0} points (quest #${entry.questId})`}
              {entry.kind === 'badge' && `Badge #${entry.badgeId} issued (token #${entry.tokenId})`}
              {entry.kind === 'attestation' &&
                `Attested completion — quest #${entry.questId}${entry.signer ? `, signed by ${formatAddress(entry.signer)}` : ''}`}
            </p>
            <p className="text-xs text-ink-500">
              Block {entry.blockNumber.toLocaleString('en-US')}
            </p>
          </div>
          {explorerTxUrl(env.NEXT_PUBLIC_CHAIN_ID, entry.hash) ? (
            <a
              href={explorerTxUrl(env.NEXT_PUBLIC_CHAIN_ID, entry.hash)}
              target="_blank"
              rel="noreferrer"
              className="font-mono text-xs text-electric-300 underline"
            >
              {formatAddress(entry.hash)} ↗
            </a>
          ) : (
            <span className="font-mono text-xs text-ink-400">{formatAddress(entry.hash)}</span>
          )}
        </li>
      ))}
    </ul>
  );
}
