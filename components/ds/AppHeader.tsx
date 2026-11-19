"use client";

import { AnodeMark } from "./AnodeMark";
import { Button } from "./Button";

export type Section = "assets" | "inspections" | "reports";

export interface AppHeaderProps {
  /** Breadcrumb levels, parent first: ["Tank T-04", "Point 3"]. The last is the current level. */
  breadcrumb: string[];
  /** Plain mono text: "SAVED 22:31", "SAVING", later "OFFLINE, WILL SYNC". */
  saveStatus: string;
  /** Account initials for the account plate. */
  initials: string;
  /** Desktop navigation: the current section. */
  current?: Section;
  homeHref?: string;
  onNewInspection?: () => void;
  onAccount?: () => void;
}

const NAV: { key: Section; label: string; href: string }[] = [
  { key: "assets", label: "Assets", href: "/assets" },
  { key: "inspections", label: "Inspections", href: "/inspections" },
  { key: "reports", label: "Reports", href: "/reports" },
];

function AccountPlate({ initials, onAccount }: { initials: string; onAccount?: (() => void) | undefined }) {
  return (
    <button
      type="button"
      aria-label="Account menu"
      onClick={onAccount}
      className="size-[34px] shrink-0 rounded-lg border border-line-strong bg-surface font-mono text-[12px] font-bold text-ink"
    >
      {initials}
    </button>
  );
}

/**
 * Header on panel with brushed grain, 1px line bottom edge, 56px tall.
 * Phone: mark, breadcrumb, save status, account plate.
 * Desktop (container 768px and wider): mark and wordmark, Assets / Inspections / Reports, search, New inspection, save status, account.
 */
export function AppHeader({ breadcrumb, saveStatus, initials, current, homeHref = "/", onNewInspection, onAccount }: AppHeaderProps) {
  const parents = breadcrumb.slice(0, -1);
  const here = breadcrumb.at(-1) ?? "";
  return (
    <div className="@container">
    <header className="ds-grain flex h-14 items-center gap-3 border-b border-line px-4 @3xl:px-12">
      <a href={homeHref} aria-label="Anode home" className="flex shrink-0 items-center gap-2 text-ink no-underline">
        <AnodeMark size={30} />
        <span className="hidden text-[22px] leading-[28px] font-bold tracking-[-0.03em] @3xl:inline" aria-hidden="true">
          anode
        </span>
      </a>

      {/* Phone: breadcrumb, truncating from the left on narrow screens. */}
      <nav aria-label="Breadcrumb" className="flex min-w-0 flex-1 justify-start @3xl:hidden">
        <div dir="rtl" className="min-w-0 overflow-hidden font-mono text-[12px] tracking-[0.08em] text-ellipsis whitespace-nowrap uppercase">
          <span dir="ltr">
            {parents.length > 0 && <span className="text-muted">{parents.join(" / ")} / </span>}
            <span className="text-ink" aria-current="page">{here}</span>
          </span>
        </div>
      </nav>

      {/* Desktop: sections, search and the primary action. */}
      <nav aria-label="Main" className="hidden flex-1 items-center gap-6 @3xl:flex">
        {NAV.map((item) => (
          <a
            key={item.key}
            href={item.href}
            aria-current={current === item.key ? "page" : undefined}
            className={`font-mono text-label uppercase no-underline ${current === item.key ? "text-ink" : "text-muted"}`}
          >
            {item.label}
          </a>
        ))}
        <form role="search" className="ml-auto" onSubmit={(e) => e.preventDefault()}>
          <label className="sr-only" htmlFor="app-search">Search assets and inspections</label>
          <input
            id="app-search"
            type="search"
            placeholder="Search"
            className="h-10 w-56 rounded-md border-[1.5px] border-line-strong bg-surface px-3 text-body text-ink placeholder:text-muted"
          />
        </form>
        <Button onClick={onNewInspection}>New inspection</Button>
      </nav>

      <span className="shrink-0 font-mono text-[11px] tracking-[0.08em] text-muted" role="status">
        {saveStatus}
      </span>
      <AccountPlate initials={initials} onAccount={onAccount} />
    </header>
    </div>
  );
}
