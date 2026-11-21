import Link from 'next/link';
import { GlassCard } from '@/components/GlassCard';
import { AgentIdStatus } from '@/components/AgentIdStatus';

const FEATURES = [
  {
    title: 'Agent Quests',
    description:
      'Daily, weekly, and community missions for Agent ID holders. Every completion is recorded on-chain.',
  },
  {
    title: 'On-chain Reputation',
    description:
      'Points grow only through validated quest completions. No admin can inflate a score by hand.',
  },
  {
    title: 'Soulbound Badges',
    description:
      'Non-transferable achievements anyone can verify on BscScan. Your record, provably yours.',
  },
  {
    title: 'Transparent Leaderboard',
    description:
      'Ranked by real validated activity — not by transaction spam or manufactured volume.',
  },
];

const STEPS = [
  {
    n: '1',
    title: 'Connect your wallet',
    text: 'Any EVM wallet. No seed phrase, no QR login, no session storage — ever.',
  },
  {
    n: '2',
    title: 'Verify your Agent ID',
    text: 'We check AgentGate on-chain — the same gate the contracts enforce. Holders only.',
  },
  {
    n: '3',
    title: 'Complete quests',
    text: 'Check in daily, join campaigns, and watch your reputation grow on-chain.',
  },
];

export default function HomePage() {
  return (
    <div className="bg-hero-glow bg-grid-lines">
      {/* Hero */}
      <section className="mx-auto max-w-6xl px-4 pb-16 pt-20 text-center sm:px-6 sm:pt-28">
        <p className="mx-auto mb-6 w-fit rounded-pill border border-agent-400/40 bg-agent-500/10 px-4 py-1.5 text-xs font-semibold uppercase tracking-widest text-agent-300">
          Binance Agent ID Hackathon — BNB Chain
        </p>
        <h1 className="mx-auto max-w-3xl text-4xl font-bold leading-tight tracking-tight sm:text-6xl">
          Your Agent ID. <span className="text-gradient">Your Onchain Reputation.</span>
        </h1>
        <p className="mx-auto mt-6 max-w-2xl text-base leading-relaxed text-ink-400 sm:text-lg">
          AGENTHUB is the activity and reputation hub for Binance Agent ID holders: quests, verified
          reputation, soulbound badges, and a leaderboard you can audit transaction by transaction.
        </p>
        <div className="mt-8 flex flex-col items-center justify-center gap-3 sm:flex-row">
          <Link
            href="/quests"
            className="rounded-pill bg-gradient-to-r from-agent-500 to-electric-600 px-7 py-3 text-sm font-semibold text-white shadow-glow-cyan transition hover:opacity-90"
          >
            Explore Quests
          </Link>
          <Link
            href="/leaderboard"
            className="rounded-pill border border-navy-600 bg-navy-800/70 px-7 py-3 text-sm font-semibold text-ink-100 transition hover:border-agent-400/60"
          >
            View Leaderboard
          </Link>
        </div>
        <GlassCard className="mx-auto mt-10 max-w-xl p-5 text-left">
          <p className="mb-2 text-xs font-semibold uppercase tracking-widest text-ink-500">
            Agent ID check — live on-chain read
          </p>
          <AgentIdStatus />
        </GlassCard>
      </section>

      {/* Features */}
      <section className="mx-auto max-w-6xl px-4 pb-16 sm:px-6">
        <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
          {FEATURES.map((feature) => (
            <GlassCard key={feature.title} className="p-5">
              <h3 className="text-base font-semibold text-ink-100">{feature.title}</h3>
              <p className="mt-2 text-sm leading-relaxed text-ink-400">{feature.description}</p>
            </GlassCard>
          ))}
        </div>
      </section>

      {/* How it works */}
      <section className="mx-auto max-w-6xl px-4 pb-20 sm:px-6">
        <h2 className="mb-8 text-center text-2xl font-bold sm:text-3xl">How it works</h2>
        <div className="grid gap-5 md:grid-cols-3">
          {STEPS.map((step) => (
            <GlassCard key={step.n} className="p-6">
              <span className="flex h-10 w-10 items-center justify-center rounded-full bg-gradient-to-br from-agent-400 to-electric-600 text-base font-bold text-white">
                {step.n}
              </span>
              <h3 className="mt-4 text-lg font-semibold text-ink-100">{step.title}</h3>
              <p className="mt-2 text-sm leading-relaxed text-ink-400">{step.text}</p>
            </GlassCard>
          ))}
        </div>
        <p className="mt-10 text-center text-sm text-ink-500">
          Contracts are live on BSC testnet — mainnet is the competition target. The frontend
          reads and writes the real deployed contracts.
        </p>
      </section>
    </div>
  );
}
