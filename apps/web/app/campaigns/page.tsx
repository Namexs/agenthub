import { GlassCard } from '@/components/GlassCard';

export const metadata = { title: 'Campaigns — AGENTHUB' };

export default function CampaignsPage() {
  return (
    <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6">
      <h1 className="text-3xl font-bold tracking-tight">Community Campaigns</h1>
      <p className="mt-2 max-w-2xl text-sm leading-relaxed text-ink-400">
        Project teams can run campaigns for Agent ID holders: create a quest, invite holders, and
        verify completion on-chain. Campaign creation opens with the Phase 2 testnet deploy.
      </p>
      <div className="mt-8 grid gap-5 md:grid-cols-2">
        <GlassCard className="p-6">
          <h2 className="text-lg font-semibold">For participants</h2>
          <p className="mt-2 text-sm leading-relaxed text-ink-400">
            Join a campaign, complete its quest, and earn reputation points plus campaign badges.
            Every completion is a transaction you can verify on BscScan.
          </p>
        </GlassCard>
        <GlassCard className="p-6">
          <h2 className="text-lg font-semibold">For campaign creators</h2>
          <p className="mt-2 text-sm leading-relaxed text-ink-400">
            Create quests with the QUEST_CREATOR_ROLE, set reward points and time windows, and track
            completions transparently. No custody of user funds — AGENTHUB never holds participant
            assets.
          </p>
        </GlassCard>
      </div>
      <GlassCard className="mt-5 p-6">
        <h2 className="text-lg font-semibold">Active campaigns</h2>
        <p className="mt-2 text-sm text-ink-400">
          No campaigns yet — the first community campaign launches with the testnet release.
        </p>
      </GlassCard>
    </div>
  );
}
