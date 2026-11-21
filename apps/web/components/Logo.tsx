// AGENTHUB logo mark: a hexagonal badge (the Agent ID) holding a
// hand-drawn-feeling "A", with a cyan node at the apex — the hub.
// Single SVG, no image asset, scales from 16px to any size.
export function Logo({ className = 'h-8 w-8' }: { className?: string }) {
  return (
    <svg viewBox="0 0 32 32" fill="none" className={className} aria-hidden="true">
      <path
        d="M16 2.5 28 9.25v13.5L16 29.5 4 22.75V9.25L16 2.5Z"
        stroke="#22d3ee"
        strokeWidth="1.8"
        strokeLinejoin="round"
      />
      <path
        d="M11 22.5 16 10l5 12.5"
        stroke="#f1f5f9"
        strokeWidth="2.2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path d="M13 18h6" stroke="#f1f5f9" strokeWidth="2.2" strokeLinecap="round" />
      <circle cx="16" cy="10" r="2.1" fill="#22d3ee" />
    </svg>
  );
}
