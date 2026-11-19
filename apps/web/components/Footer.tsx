import Link from 'next/link';

export function Footer() {
  return (
    <footer className="border-t border-navy-600/50 py-8">
      <div className="mx-auto flex max-w-6xl flex-col gap-4 px-4 text-sm text-ink-500 sm:flex-row sm:items-center sm:justify-between sm:px-6">
        <p>AGENTHUB — Your Agent ID. Your Onchain Reputation.</p>
        <div className="flex gap-5">
          <Link href="/security" className="transition hover:text-agent-300">
            Security
          </Link>
          <Link href="/history" className="transition hover:text-agent-300">
            Activity
          </Link>
          <a
            href="https://www.binance.com/en/support/announcement/detail/95f5dbe0ea674a48a739b59e046648bf"
            target="_blank"
            rel="noreferrer"
            className="transition hover:text-agent-300"
          >
            Hackathon
          </a>
        </div>
      </div>
    </footer>
  );
}
