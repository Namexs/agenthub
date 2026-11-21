import { GlassCard } from '@/components/GlassCard';

export const metadata = { title: 'Security | AGENTHUB' };

const COMMITMENTS = [
  {
    title: 'Non-custodial by design',
    text: 'AGENTHUB never holds your assets. Quests, reputation, and badges are records, not funds. There is nothing to drain.',
  },
  {
    title: 'No credentials, ever',
    text: 'We never ask for seed phrases, private keys, API secrets, or pairing codes. Anyone asking for them in our name is a scam.',
  },
  {
    title: 'No QR login, no session storage',
    text: 'You sign in with your own wallet, in your own app. We never store login sessions or transact on your behalf.',
  },
  {
    title: 'Every action is your transaction',
    text: 'Quest completions are transactions you review and confirm in your wallet. No hidden transfers, no unlimited approvals.',
  },
  {
    title: 'Open-source contracts',
    text: 'All contract source is public and verified on BscScan. Owner permissions are documented in docs/SECURITY.md.',
  },
  {
    title: 'Reputation cannot be bought or faked',
    text: 'Points only increase through validated quest completions. Admins cannot grant themselves scores.',
  },
];

export default function SecurityPage() {
  return (
    <div className="mx-auto max-w-6xl px-4 py-10 sm:px-6">
      <h1 className="text-3xl font-bold tracking-tight">Security</h1>
      <p className="mt-2 max-w-2xl text-sm leading-relaxed text-ink-400">
        Security first, in writing. These commitments are enforced by the contract architecture,
        not by promises. Full details live in the repository at docs/SECURITY.md.
      </p>
      <div className="mt-8 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
        {COMMITMENTS.map((item) => (
          <GlassCard key={item.title} className="p-5">
            <h2 className="text-base font-semibold text-ink-100">{item.title}</h2>
            <p className="mt-2 text-sm leading-relaxed text-ink-400">{item.text}</p>
          </GlassCard>
        ))}
      </div>
    </div>
  );
}
