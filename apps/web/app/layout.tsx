import type { Metadata } from 'next';
import { Inter, Space_Grotesk, IBM_Plex_Mono } from 'next/font/google';
import { Providers } from '@/lib/providers';
import { Navbar } from '@/components/Navbar';
import { ChainGuard } from '@/components/ChainGuard';
import { Footer } from '@/components/Footer';
import './globals.css';

const inter = Inter({ subsets: ['latin'], variable: '--font-inter' });
const display = Space_Grotesk({
  subsets: ['latin'],
  variable: '--font-display',
  weight: ['500', '600', '700'],
});
const plexMono = IBM_Plex_Mono({
  subsets: ['latin'],
  variable: '--font-plex-mono',
  weight: ['400', '500', '600'],
});

export const metadata: Metadata = {
  title: 'AGENTHUB: Your Agent ID. Your Onchain Reputation.',
  description:
    'Activity and reputation platform for Binance Agent ID holders: quests, on-chain reputation, soulbound badges, and a transparent leaderboard on BNB Chain.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${inter.variable} ${display.variable} ${plexMono.variable}`}>
      <body className="min-h-screen bg-navy-950 font-sans text-ink-100">
        <Providers>
          <div className="flex min-h-screen flex-col">
            <Navbar />
            <ChainGuard />
            <main className="flex-1">{children}</main>
            <Footer />
          </div>
        </Providers>
      </body>
    </html>
  );
}
