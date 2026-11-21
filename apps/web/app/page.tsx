import Link from 'next/link';
import { AgentIdStatus } from '@/components/AgentIdStatus';

function QuestGlyph() {
  return (
    <svg viewBox="0 0 24 24" fill="none" className="h-5 w-5" aria-hidden="true">
      <circle cx="12" cy="12" r="9" stroke="currentColor" strokeWidth="1.6" />
      <circle cx="12" cy="12" r="4.5" stroke="currentColor" strokeWidth="1.6" />
      <circle cx="12" cy="12" r="1.4" fill="currentColor" />
    </svg>
  );
}

function ReputationGlyph() {
  return (
    <svg viewBox="0 0 24 24" fill="none" className="h-5 w-5" aria-hidden="true">
      <path d="M4 20h16" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
      <path d="M7 20v-5" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
      <path d="M12 20V8" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
      <path d="M17 20v-9" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
    </svg>
  );
}

function BadgeGlyph() {
  return (
    <svg viewBox="0 0 24 24" fill="none" className="h-5 w-5" aria-hidden="true">
      <path
        d="M12 2.8 20 7.3v9.4l-8 4.5-8-4.5V7.3l8-4.5Z"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinejoin="round"
      />
      <path
        d="m8.8 12.2 2.2 2.2 4.2-4.6"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function LeaderboardGlyph() {
  return (
    <svg viewBox="0 0 24 24" fill="none" className="h-5 w-5" aria-hidden="true">
      <path d="M4 6h3.5M11 6h9M4 12h3.5M11 12h9M4 18h3.5M11 18h5" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
    </svg>
  );
}

/* Faint oversized hexagon motif behind the hero, an echo of the logo
   mark, kept barely visible so the page feels branded, not decorated. */
function HeroMark() {
  return (
    <svg
      viewBox="0 0 400 400"
      fill="none"
      aria-hidden="true"
      className="pointer-events-none absolute -right-28 top-4 hidden h-[26rem] w-[26rem] text-agent-400 opacity-[0.08] md:block"
    >
      <path
        d="M200 10 364.5 105v190L200 390 35.5 295V105L200 10Z"
        stroke="currentColor"
        strokeWidth="1"
      />
      <path
        d="M200 70 312.6 135v130L200 330 87.4 265V135L200 70Z"
        stroke="currentColor"
        strokeWidth="1"
      />
      <circle cx="200" cy="10" r="4" fill="currentColor" />
      <circle cx="364.5" cy="295" r="4" fill="currentColor" />
      <circle cx="35.5" cy="105" r="4" fill="currentColor" />
      <circle cx="200" cy="200" r="4" fill="currentColor" />
    </svg>
  );
}

const FEATURES = [
  {
    glyph: <QuestGlyph />,
    title: 'Agent Quests',
    description:
      'Daily, weekly, and community missions for Agent ID holders. Every completion is recorded on-chain.',
  },
  {
    glyph: <ReputationGlyph />,
    title: 'On-chain Reputation',
    description:
      'Points grow only through validated quest completions. No admin can inflate a score by hand.',
  },
  {
    glyph: <BadgeGlyph />,
    title: 'Soulbound Badges',
    description:
      'Non-transferable achievements anyone can verify on BscScan. Your record stays yours.',
  },
  {
    glyph: <LeaderboardGlyph />,
    title: 'Transparent Leaderboard',
    description:
      'Ranked by real validated activity, not by transaction spam or manufactured volume.',
  },
];

const STEPS = [
  {
    n: '1',
    title: 'Connect your wallet',
    text: 'Any EVM wallet. No seed phrase, no QR login, and nothing is stored in a session.',
  },
  {
    n: '2',
    title: 'Verify your Agent ID',
    text: 'We check AgentGate on-chain, the same gate the contracts enforce. Holders only.',
  },
  {
    n: '3',
    title: 'Complete quests',
    text: 'Check in daily, join campaigns, and watch your reputation grow on-chain.',
  },
];

export default function HomePage() {
  return (
    <div className="bg-hero-glow">
      {/* Hero */}
      <section className="bg-dot-grid relative overflow-hidden">
        <HeroMark />
        <div className="relative mx-auto max-w-6xl px-4 pb-16 pt-16 sm:px-6 sm:pt-24">
          <p className="flex items-center gap-2.5 font-mono text-[11px] font-medium uppercase tracking-[0.12em] text-agent-300 sm:text-xs sm:tracking-[0.2em]">
            <span className="relative flex h-2 w-2">
              <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-agent-400 opacity-60" />
              <span className="relative inline-flex h-2 w-2 rounded-full bg-agent-400" />
            </span>
            Binance Agent ID Hackathon on BNB Chain
          </p>
          <h1 className="mt-7 max-w-3xl font-display text-5xl font-bold leading-[1.04] tracking-tight text-ink-100 sm:text-7xl">
            Your Agent ID.
            <br />
            <span className="text-agent-400">Your Onchain Reputation.</span>
          </h1>
          <p className="mt-6 max-w-xl text-base leading-relaxed text-ink-400 sm:text-lg">
            AGENTHUB is the activity and reputation hub for Binance Agent ID holders: quests,
            verified reputation, soulbound badges, and a leaderboard you can audit transaction by
            transaction.
          </p>
          <div className="mt-9 flex flex-wrap items-center gap-3">
            <Link
              href="/quests"
              className="rounded-lg bg-agent-400 px-6 py-3 text-sm font-semibold text-navy-950 transition-colors hover:bg-agent-300"
            >
              Explore Quests
            </Link>
            <Link
              href="/leaderboard"
              className="rounded-lg border border-navy-600 px-6 py-3 text-sm font-semibold text-ink-100 transition-colors hover:border-ink-400 hover:bg-navy-900"
            >
              View Leaderboard
            </Link>
          </div>
          <div className="mt-12 max-w-2xl rounded-xl border border-navy-600/50 border-l-2 border-l-agent-400 bg-navy-900 p-5 shadow-card">
            <p className="mb-2 font-mono text-[11px] font-medium uppercase tracking-[0.18em] text-ink-500">
              Agent ID check: live on-chain read
            </p>
            <AgentIdStatus />
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="mx-auto max-w-6xl px-4 py-14 sm:px-6">
        <div className="grid gap-px overflow-hidden rounded-xl border border-navy-600/40 bg-navy-600/40 sm:grid-cols-2 lg:grid-cols-4">
          {FEATURES.map((feature, i) => (
            <div
              key={feature.title}
              className="group bg-navy-950 p-6 transition-colors hover:bg-navy-900"
            >
              <div className="flex items-center justify-between">
                <span className="text-agent-400 transition-transform duration-300 group-hover:-translate-y-0.5">
                  {feature.glyph}
                </span>
                <span className="font-mono text-xs text-ink-500">0{i + 1}</span>
              </div>
              <h3 className="mt-5 font-display text-base font-semibold text-ink-100">
                {feature.title}
              </h3>
              <p className="mt-2 text-sm leading-relaxed text-ink-400">{feature.description}</p>
            </div>
          ))}
        </div>
      </section>

      {/* How it works */}
      <section className="mx-auto max-w-6xl px-4 pb-20 pt-2 sm:px-6">
        <h2 className="font-display text-2xl font-bold tracking-tight sm:text-3xl">How it works</h2>
        <div className="mt-9 grid gap-10 md:grid-cols-3">
          {STEPS.map((step) => (
            <div key={step.n} className="border-t-2 border-navy-600 pt-6">
              <span className="font-display text-5xl font-bold leading-none text-navy-500">
                0{step.n}
              </span>
              <h3 className="mt-4 font-display text-lg font-semibold text-ink-100">
                {step.title}
              </h3>
              <p className="mt-2 text-sm leading-relaxed text-ink-400">{step.text}</p>
            </div>
          ))}
        </div>
        <p className="mt-14 border-t border-navy-600/40 pt-6 text-sm text-ink-500">
          Contracts are live on BSC testnet. Mainnet is the competition target. The frontend
          reads and writes the real deployed contracts.
        </p>
      </section>
    </div>
  );
}
