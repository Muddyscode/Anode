export type Destination = "assets" | "capture" | "reports";

export interface BottomBarProps {
  current?: Destination;
  /** Findings waiting for sign-off. The count plate is hidden at zero. */
  reportsCount: number;
  assetsHref?: string;
  captureHref?: string;
  reportsHref?: string;
}

const AssetIcon = () => (
  <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true">
    <rect x="3" y="10" width="18" height="10" rx="1" />
    <path d="M7 10V6h10v4" />
    <path d="M3 15h18" />
  </svg>
);

const CameraIcon = () => (
  <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="var(--on-cobalt)" strokeWidth="1.8" aria-hidden="true">
    <path d="M4 8h3l2-3h6l2 3h3v11H4z" />
    <circle cx="12" cy="13" r="3.5" />
  </svg>
);

const ReportIcon = () => (
  <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true">
    <path d="M6 3h9l4 4v14H6z" />
    <path d="M9 12h7M9 16h7" />
  </svg>
);

const label = "flex w-20 flex-col items-center gap-1 font-mono text-[10px] tracking-[0.1em] uppercase no-underline";

/**
 * Phone navigation: 76px, panel with brushed grain, 1px line top edge. Capture is the raised
 * cobalt square and the only way to start an inspection on phone. Hidden on desktop
 * (container 768px and wider), where the header holds navigation.
 */
export function BottomBar({ current, reportsCount, assetsHref = "/assets", captureHref = "/capture", reportsHref = "/reports" }: BottomBarProps) {
  return (
    <div className="@container">
    <nav aria-label="Main" className="ds-grain flex h-[76px] items-center justify-around border-t border-line px-3 pb-[6px] @3xl:hidden">
      <a href={assetsHref} aria-current={current === "assets" ? "page" : undefined} className={`${label} ${current === "assets" ? "text-ink" : "text-muted"}`}>
        <AssetIcon />
        Assets
      </a>
      <a
        href={captureHref}
        aria-label="Capture"
        aria-current={current === "capture" ? "page" : undefined}
        className="-mt-[26px] flex size-[60px] items-center justify-center rounded-lg bg-cobalt"
        style={{ boxShadow: "0 0 0 4px var(--ground)" }}
      >
        <CameraIcon />
      </a>
      <a
        href={reportsHref}
        aria-current={current === "reports" ? "page" : undefined}
        aria-label={reportsCount > 0 ? `Reports, ${reportsCount} waiting for sign-off` : "Reports"}
        className={`${label} ${current === "reports" ? "text-ink" : "text-muted"}`}
      >
        <span className="relative block size-[22px]">
          <ReportIcon />
          {reportsCount > 0 && (
            <span
              aria-hidden="true"
              className="absolute -top-[6px] -right-3 h-4 min-w-4 rounded-sm bg-ink px-[3px] text-center text-[10px] leading-4 text-ground"
            >
              {reportsCount}
            </span>
          )}
        </span>
        <span aria-hidden="true">Reports</span>
      </a>
    </nav>
    </div>
  );
}
