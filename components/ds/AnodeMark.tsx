/**
 * The Anode mark: a ring (the structure) with a small square attached (the sacrificial anode).
 * Same geometry as design/anode-mark.svg; drawn with ink and cobalt so it follows the theme.
 * Part of AppHeader, not a separate component of the system.
 */
export function AnodeMark({ size = 30, title }: { size?: number; title?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 44 44" role={title ? "img" : undefined} aria-hidden={title ? undefined : true} aria-label={title}>
      <circle cx="19" cy="19" r="13" fill="none" stroke="var(--ink)" strokeWidth="4" />
      <line x1="28.5" y1="28.5" x2="33" y2="33" stroke="var(--ink)" strokeWidth="3" strokeLinecap="round" />
      <rect x="31" y="31" width="11" height="11" rx="2.5" fill="var(--cobalt)" />
    </svg>
  );
}
