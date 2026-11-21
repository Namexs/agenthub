import Link from 'next/link';
import { ConnectButton } from './ConnectButton';
import { Logo } from './Logo';

const LINKS = [
  { href: '/quests', label: 'Quests' },
  { href: '/leaderboard', label: 'Leaderboard' },
  { href: '/campaigns', label: 'Campaigns' },
  { href: '/dashboard', label: 'Dashboard' },
  { href: '/security', label: 'Security' },
];

export function Navbar() {
  return (
    <header className="sticky top-0 z-50 border-b border-navy-600/40 bg-navy-950/85 backdrop-blur">
      <nav className="mx-auto flex h-16 max-w-6xl items-center justify-between px-4 sm:px-6">
        <Link href="/" className="flex items-center gap-2.5">
          <Logo className="h-8 w-8" />
          <span className="font-display text-lg font-bold tracking-tight text-ink-100">
            AGENTHUB
          </span>
        </Link>
        <div className="hidden items-center gap-6 md:flex">
          {LINKS.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="text-sm font-medium text-ink-400 transition-colors hover:text-ink-100"
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
            className="whitespace-nowrap text-sm font-medium text-ink-400"
          >
            {link.label}
          </Link>
        ))}
      </nav>
    </header>
  );
}
