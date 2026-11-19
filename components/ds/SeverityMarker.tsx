import { SEVERITY, type Severity } from "./severity";

export interface SeverityMarkerProps {
  severity: Severity;
  /** Slide in from the left on entry (dur-marker). Reduced motion: it simply appears. */
  animate?: boolean;
}

/**
 * A solid pipe-marker band in the severity colour, with an arrow end, holding the code, the name
 * and the action. The code is always printed; severity is never a dot or a coloured word alone.
 */
export function SeverityMarker({ severity, animate = true }: SeverityMarkerProps) {
  const s = SEVERITY[severity];
  return (
    <div className="overflow-hidden" role="group" aria-label={`Severity ${severity}, ${s.name}. ${s.action}.`}>
      <div
        className={`flex min-h-11 flex-wrap items-center gap-x-[14px] py-[13px] pr-[38px] pl-4 ${animate ? "ds-marker-in" : ""}`}
        style={{
          background: s.fill,
          color: s.text,
          clipPath: "polygon(0 0, calc(100% - 22px) 0, 100% 50%, calc(100% - 22px) 100%, 0 100%)",
        }}
      >
        <span className="font-mono text-[15px] leading-[18px] font-bold">{severity}</span>
        <span className="font-mono text-marker uppercase">{s.name}</span>
        <span className="ml-auto text-[14px] leading-[18px] font-semibold">{s.action}</span>
      </div>
    </div>
  );
}
