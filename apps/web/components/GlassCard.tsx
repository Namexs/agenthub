import type { ReactNode } from 'react';
import { cn } from '@/lib/utils';

export function GlassCard({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div
      className={cn(
        'rounded-card border border-navy-600/60 bg-navy-800/60 shadow-glass backdrop-blur-glass',
        className,
      )}
    >
      {children}
    </div>
  );
}
