export interface NameplateProps {
  /** The standard the grade cites, as a label: "ISO 4628-3". */
  standard: string;
  /** ISO 4628-3 Ri, 0 to 5. */
  grade: number;
  /** Measured percent of area rusted, 0 to 100. */
  percentRusted: number;
}

const Rivet = ({ position }: { position: string }) => (
  <span aria-hidden="true" className={`absolute size-[5px] rounded-full border border-muted ${position}`} />
);

/** The grade, stamped on an equipment nameplate. Rivets appear on the nameplate only. */
export function Nameplate({ standard, grade, percentRusted }: NameplateProps) {
  const pct = percentRusted.toFixed(2);
  return (
    <div
      role="group"
      aria-label={`Grade Ri ${grade}, ${pct} percent rusted, ${standard}`}
      className="ds-grain relative w-[220px] rounded-md border-[1.5px] border-line-strong px-[18px] py-[14px]"
    >
      <Rivet position="left-[6px] top-[6px]" />
      <Rivet position="right-[6px] top-[6px]" />
      <Rivet position="left-[6px] bottom-[6px]" />
      <Rivet position="right-[6px] bottom-[6px]" />
      <div aria-hidden="true">
        <div className="font-mono text-label text-muted uppercase">{standard}</div>
        <div className="font-mono text-grade text-ink">Ri {grade}</div>
        <div className="font-mono text-readout text-muted">{pct}% RUSTED</div>
      </div>
    </div>
  );
}
