import type { ReactNode } from 'react';
import { cn } from '@/lib/utils';

export function GlassCard({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div
      className={cn(
        'rounded-xl border border-navy-600/50 bg-navy-900 shadow-card',
        className,
      )}
    >
      {children}
    </div>
  );
}
