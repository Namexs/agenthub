'use client';

import { useChainGuard } from '@/hooks/useChainGuard';

// Wrong-network banner (Phase 7). Rendered globally below the navbar:
// when the connected wallet is on a different chain than the app
// targets, nothing on the page can be trusted as this chain's data, so
// the banner says so plainly and offers a one-click switch.
export function ChainGuard() {
  const {
    isConnected,
    isSupported,
    currentChainName,
    expectedChainName,
    isSwitching,
    switchToExpected,
  } = useChainGuard();

  if (!isConnected || isSupported) return null;

  return (
    <div className="border-b border-amber-500/40 bg-amber-500/10 px-4 py-3">
      <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-3 sm:px-6">
        <p className="text-sm text-amber-200">
          Your wallet is on <span className="font-semibold">{currentChainName}</span>, but this app
          targets <span className="font-semibold">{expectedChainName}</span>. Switch networks to see
          live data and complete quests.
        </p>
        <button
          type="button"
          onClick={switchToExpected}
          disabled={isSwitching}
          className="rounded-lg bg-amber-500 px-4 py-1.5 text-sm font-semibold text-navy-950 transition hover:opacity-90 disabled:opacity-50"
        >
          {isSwitching ? 'Switching…' : `Switch to ${expectedChainName}`}
        </button>
      </div>
    </div>
  );
}
