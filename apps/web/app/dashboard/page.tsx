import { GlassCard } from '@/components/GlassCard';
import { AgentIdStatus } from '@/components/AgentIdStatus';

export const metadata = { title: 'Dashboard — AGENTHUB' };

export default function DashboardPage() {
  return (
    <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6">
      <h1 className="text-3xl font-bold tracking-tight">Dashboard</h1>
      <p className="mt-2 text-sm text-ink-400">
        Your Agent ID activity at a glance. Live on-chain data appears once the contracts are
        deployed (Phase 2).
      </p>
      <div className="mt-8 grid gap-5 md:grid-cols-3">
        <GlassCard className="p-5">
          <p className="text-xs font-semibold uppercase tracking-widest text-ink-500">Agent ID</p>
          <div className="mt-3">
            <AgentIdStatus />
          </div>
        </GlassCard>
        <GlassCard className="p-5">
          <p className="text-xs font-semibold uppercase tracking-widest text-ink-500">Reputation</p>
          <p className="mt-3 text-2xl font-bold text-ink-100">— pts</p>
          <p className="mt-1 text-sm text-ink-400">
            Level — · Reputation contract not deployed yet
          </p>
        </GlassCard>
        <GlassCard className="p-5">
          <p className="text-xs font-semibold uppercase tracking-widest text-ink-500">
            Quests completed
          </p>
          <p className="mt-3 text-2xl font-bold text-ink-100">—</p>
          <p className="mt-1 text-sm text-ink-400">QuestManager not deployed yet</p>
        </GlassCard>
      </div>
      <GlassCard className="mt-5 p-5">
        <h2 className="text-lg font-semibold">Recent activity</h2>
        <p className="mt-2 text-sm text-ink-400">
          No on-chain activity yet. Completed quests and earned badges will show up here with links
          to BscScan.
        </p>
      </GlassCard>
    </div>
  );
}
