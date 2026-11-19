import type { CSSProperties } from "react";
import { SEVERITY, type Severity } from "./severity";

export interface SeverityGaugeProps {
  severity: Severity;
  confidence: "low" | "medium" | "high";
  /** Sweep, overshoot once and settle (dur-needle). Reduced motion: drawn at rest. */
  animate?: boolean;
}

/**
 * A pressure-gauge dial with four equal arcs (sev-1 to sev-4) and an ink needle at the middle of
 * the current severity's arc. Always paired with a SeverityMarker.
 */
export function SeverityGauge({ severity, confidence, animate = true }: SeverityGaugeProps) {
  const needle = { "--needle-angle": `${SEVERITY[severity].needleAngle}deg` } as CSSProperties;
  return (
    <div className="flex w-[150px] flex-col items-center gap-1 rounded-md border-[1.5px] border-line-strong bg-surface p-[10px]">
      <svg width="130" height="80" viewBox="0 0 120 74" role="img" aria-label={`Severity gauge reading ${severity}, ${SEVERITY[severity].name}`}>
        <path d="M12 60 A48 48 0 0 1 26.06 26.06" fill="none" stroke="var(--sev-1)" strokeWidth="9" />
        <path d="M26.06 26.06 A48 48 0 0 1 60 12" fill="none" stroke="var(--sev-2)" strokeWidth="9" />
        <path d="M60 12 A48 48 0 0 1 93.94 26.06" fill="none" stroke="var(--sev-3)" strokeWidth="9" />
        <path d="M93.94 26.06 A48 48 0 0 1 108 60" fill="none" stroke="var(--sev-4)" strokeWidth="9" />
        <line
          className="ds-needle"
          style={animate ? needle : { ...needle, animation: "none" }}
          x1="60"
          y1="60"
          x2="22"
          y2="60"
          stroke="var(--ink)"
          strokeWidth="3"
          strokeLinecap="round"
        />
        <circle cx="60" cy="60" r="5" fill="var(--ink)" />
        <text x="6" y="72" fontFamily="var(--font-mono)" fontSize="9" fill="var(--muted)">S1</text>
        <text x="114" y="72" textAnchor="end" fontFamily="var(--font-mono)" fontSize="9" fill="var(--muted)">S4</text>
      </svg>
      <div className="font-mono text-label text-muted uppercase">Confidence {confidence}</div>
    </div>
  );
}
