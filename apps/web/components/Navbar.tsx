import Link from 'next/link';
import { ConnectButton } from './ConnectButton';

const LINKS = [
  { href: '/quests', label: 'Quests' },
  { href: '/leaderboard', label: 'Leaderboard' },
  { href: '/campaigns', label: 'Campaigns' },
  { href: '/dashboard', label: 'Dashboard' },
  { href: '/security', label: 'Security' },
];

export function Navbar() {
  return (
    <header className="sticky top-0 z-50 border-b border-navy-600/50 bg-navy-950/80 backdrop-blur-glass">
      <nav className="mx-auto flex h-16 max-w-6xl items-center justify-between px-4 sm:px-6">
        <Link href="/" className="flex items-center gap-2">
          <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-gradient-to-br from-agent-400 to-electric-600 text-base font-bold text-white">
            A
          </span>
          <span className="text-lg font-bold tracking-tight text-ink-100">
            AGENT<span className="text-agent-400">HUB</span>
          </span>
        </Link>
        <div className="hidden items-center gap-6 md:flex">
          {LINKS.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="text-sm font-medium text-ink-300 transition hover:text-agent-300"
            >
              {link.label}
            </Link>
          ))}
        </div>
        <ConnectButton />
      </nav>
      <nav className="flex gap-5 overflow-x-auto border-t border-navy-700/40 px-4 py-2 md:hidden">
        {LINKS.map((link) => (
          <Link
            key={link.href}
            href={link.href}
            className="whitespace-nowrap text-sm font-medium text-ink-300"
          >
            {link.label}
          </Link>
        ))}
      </nav>
    </header>
  );
}
