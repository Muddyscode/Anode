"use client";

import { useEffect, useState } from "react";
import {
  AppHeader,
  BottomBar,
  Button,
  Nameplate,
  PhotoFrame,
  SEVERITIES,
  SeverityGauge,
  SeverityMarker,
  type OutlineCoordinates,
} from "@/components/ds";
import {
  COLORS,
  CONTRAST_PAIRS,
  MIN_SEVERITY_DELTA_E,
  VISIONS,
  colorOf,
  contrast,
  deltaE,
  tokens,
  type Theme,
} from "@/design/color";

type ThemeChoice = "system" | "light" | "dark";

/** A sample outline for previews: a patch of rust on a 358 x 240 photo, in image pixels. */
const SAMPLE_OUTLINE: OutlineCoordinates = [
  [[[84, 66], [112, 45], [150, 42], [185, 55], [200, 72], [240, 86], [262, 110], [252, 138], [225, 170], [190, 192], [142, 182], [100, 150], [78, 110], [84, 66]]],
];

function Section({ id, title, children }: { id: string; title: string; children: React.ReactNode }) {
  return (
    <section aria-labelledby={id} className="flex flex-col gap-4 border-t border-line pt-8">
      <h2 id={id} className="m-0 text-title text-ink">{title}</h2>
      {children}
    </section>
  );
}

function Label({ children }: { children: React.ReactNode }) {
  return <div className="font-mono text-label text-muted uppercase">{children}</div>;
}

function Swatch({ hex }: { hex: string }) {
  return <span aria-hidden="true" className="inline-block size-6 shrink-0 rounded-sm border border-line" style={{ background: hex }} />;
}

function Ratio({ value, min }: { value: number; min: number }) {
  const ok = value >= min;
  return (
    <span className={`font-mono text-readout ${ok ? "text-ink" : "text-danger-text"}`}>
      {value.toFixed(2)}:1 {ok ? "PASS" : "FAIL"}
    </span>
  );
}

export function DesignSystem() {
  const [theme, setTheme] = useState<ThemeChoice>("system");
  const [replay, setReplay] = useState(0);

  useEffect(() => {
    const root = document.documentElement;
    if (theme === "system") delete root.dataset.theme;
    else root.dataset.theme = theme;
  }, [theme]);

  const themes: Theme[] = ["light", "dark"];
  const styles = tokens.type.groups.flatMap((g) => g.styles.map((s) => ({ ...s, family: g.family })));

  return (
    <div className="min-h-dvh bg-ground">
      <AppHeader breadcrumb={["Design system", "Galvanic Steel"]} saveStatus={`TOKENS V${tokens.version}`} initials="MO" />

      <main className="mx-auto flex max-w-[1120px] flex-col gap-8 px-4 py-8 md:px-12">
        <div className="flex flex-col gap-3">
          <Label>Anode design system</Label>
          <h1 className="m-0 text-display text-ink">Galvanic Steel</h1>
          <p className="m-0 max-w-[640px] text-body text-muted">
            Brushed zinc, blueprint linework and pipe-marker labels. Cobalt is for actions; severity owns the warning
            colours. Every value on this page is generated from design/tokens.json.
          </p>
          <div className="flex flex-wrap items-center gap-3" role="group" aria-label="Theme">
            {(["system", "light", "dark"] as const).map((t) => (
              <Button key={t} variant="secondary" aria-pressed={theme === t} onClick={() => setTheme(t)}>
                {t === "system" ? "System theme" : t === "light" ? "Light" : "Dark"}
              </Button>
            ))}
            <Button variant="secondary" onClick={() => setReplay((n) => n + 1)}>
              Replay motion
            </Button>
          </div>
          <div className="font-mono text-label text-muted uppercase" aria-live="polite">
            Theme: {theme}
          </div>
        </div>

        <Section id="colour" title="Colour">
          <div className="grid gap-3 md:grid-cols-2">
            {COLORS.map((c) => (
              <div key={c.name} className="flex gap-3 rounded-md border border-line bg-surface p-3">
                <div className="flex flex-col gap-1">
                  <Swatch hex={c.value.light} />
                  <Swatch hex={c.value.dark} />
                </div>
                <div className="flex min-w-0 flex-col gap-1">
                  <div className="font-mono text-readout text-ink">{c.name}</div>
                  <div className="font-mono text-label text-muted">LIGHT {c.value.light}  DARK {c.value.dark}</div>
                  <div className="text-body text-muted">{c.usage}</div>
                </div>
              </div>
            ))}
          </div>
        </Section>

        <Section id="contrast" title="Contrast (WCAG AA)">
          <div className="overflow-x-auto">
            <table className="w-full border-collapse text-left text-body">
              <thead>
                <tr className="border-b border-line">
                  <th className="py-2 pr-4 font-mono text-label text-muted uppercase">Pair</th>
                  <th className="py-2 pr-4 font-mono text-label text-muted uppercase">Use</th>
                  <th className="py-2 pr-4 font-mono text-label text-muted uppercase">Needs</th>
                  {themes.map((t) => (
                    <th key={t} className="py-2 pr-4 font-mono text-label text-muted uppercase">{t}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {CONTRAST_PAIRS.map((p) => (
                  <tr key={`${p.fg}-${p.bg}`} className="border-b border-line">
                    <td className="py-2 pr-4 font-mono text-readout">{p.fg} on {p.bg}</td>
                    <td className="py-2 pr-4 text-muted">{p.why}</td>
                    <td className="py-2 pr-4 font-mono text-readout">{p.min}:1</td>
                    {themes.map((t) => (
                      <td key={t} className="py-2 pr-4">
                        <Ratio value={contrast(colorOf(p.fg, t), colorOf(p.bg, t))} min={p.min} />
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Section>

        <Section id="severity-vision" title="Severity colours for colour-blind users">
          <p className="m-0 max-w-[640px] text-body text-muted">
            Closest pair of severity colours, as seen with each type of colour vision (CIE76 ΔE; minimum {MIN_SEVERITY_DELTA_E}).
            The code, name and gauge position always state the severity too.
          </p>
          <div className="flex flex-wrap gap-3">
            {VISIONS.map((v) => {
              let worst = { d: Infinity, pair: "" };
              SEVERITIES.forEach((a, i) =>
                SEVERITIES.slice(i + 1).forEach((b) => {
                  const d = deltaE(colorOf(`sev-${a[1]}`, "light"), colorOf(`sev-${b[1]}`, "light"), v);
                  if (d < worst.d) worst = { d, pair: `${a}–${b}` };
                }),
              );
              return (
                <div key={v} className="flex flex-col gap-1 rounded-md border border-line bg-surface p-3">
                  <Label>{v}</Label>
                  <div className="font-mono text-readout">ΔE {worst.d.toFixed(1)} ({worst.pair})</div>
                </div>
              );
            })}
          </div>
        </Section>

        <Section id="type" title="Type">
          <div className="flex flex-col gap-4">
            {styles.map((s) => (
              <div key={s.name} className="flex flex-col gap-1">
                <Label>
                  {s.name}  {s.family}  {s.fontSize}/{s.lineHeight}  {s.fontWeight}
                </Label>
                <div className={`text-${s.name} ${s.family === "mono" ? "font-mono" : "font-sans"} ${s.name === "label" || s.name === "marker" ? "uppercase" : ""}`}>
                  {s.sample}
                </div>
              </div>
            ))}
          </div>
        </Section>

        <Section id="space" title="Spacing, radius and motion">
          <div className="grid gap-6 md:grid-cols-3">
            <div className="flex flex-col gap-2">
              {tokens.spacing.tokens.map((t) => (
                <div key={t.name} className="flex items-center gap-3">
                  <span aria-hidden="true" className="h-3 bg-cobalt" style={{ width: t.value }} />
                  <span className="font-mono text-readout">{t.name} {t.value}</span>
                </div>
              ))}
            </div>
            <div className="flex flex-col gap-2">
              {tokens.radius.tokens.map((t) => (
                <div key={t.name} className="flex items-center gap-3">
                  <span aria-hidden="true" className="size-10 border-[1.5px] border-line-strong bg-surface" style={{ borderRadius: t.value }} />
                  <span className="font-mono text-readout">{t.name} {t.value}</span>
                </div>
              ))}
            </div>
            <div className="flex flex-col gap-2">
              {tokens.duration.tokens.map((t) => (
                <div key={t.name} className="flex flex-col">
                  <span className="font-mono text-readout">{t.name} {t.value}</span>
                  <span className="text-body text-muted">{t.usage}</span>
                </div>
              ))}
            </div>
          </div>
        </Section>

        <div key={replay} className="flex flex-col gap-8">
          <Section id="button" title="Button">
            <div className="flex flex-wrap items-center gap-3">
              <Button>Sign finding</Button>
              <Button variant="secondary">Retake photo</Button>
              <Button variant="escalate">Escalate to inspector</Button>
              <Button disabled disabledReason="Add a scale card to grade">Grade photo</Button>
            </div>
          </Section>

          <Section id="severity-marker" title="SeverityMarker">
            <div className="flex max-w-[640px] flex-col gap-[10px]">
              {SEVERITIES.map((s) => (
                <SeverityMarker key={s} severity={s} />
              ))}
            </div>
          </Section>

          <Section id="severity-gauge" title="SeverityGauge">
            <div className="flex flex-wrap gap-4">
              <SeverityGauge severity="S1" confidence="high" />
              <SeverityGauge severity="S2" confidence="high" />
              <SeverityGauge severity="S3" confidence="medium" />
              <SeverityGauge severity="S4" confidence="low" />
            </div>
          </Section>

          <Section id="nameplate" title="Nameplate">
            <div className="flex flex-wrap gap-4">
              <Nameplate standard="ISO 4628-3" grade={3} percentRusted={1.02} />
              <Nameplate standard="ISO 4628-3" grade={1} percentRusted={0.05} />
            </div>
          </Section>

          <Section id="photo-frame" title="PhotoFrame">
            <div className="grid gap-6 md:grid-cols-3">
              <div className="flex flex-col gap-2">
                <Label>Measured</Label>
                <PhotoFrame alt="Tank shell, coated, with a patch of rust" widthPx={358} heightPx={240} outline={SAMPLE_OUTLINE} state="measured" caption="Tank shell, coated" scaleLabel="ANODE SCALE 50 MM" />
              </div>
              <div className="flex flex-col gap-2">
                <Label>Measuring</Label>
                <PhotoFrame alt="Tank shell, coated, being measured" widthPx={358} heightPx={240} outline={SAMPLE_OUTLINE} state="measuring" caption="Tank shell, coated" scaleLabel="ANODE SCALE 50 MM" />
              </div>
              <div className="flex flex-col gap-2">
                <Label>Rejected</Label>
                <PhotoFrame alt="Tank shell, no scale reference" widthPx={358} heightPx={240} state="rejected" caption="Tank shell, coated" rejectionReason="No scale reference found" />
              </div>
            </div>
          </Section>

          <Section id="app-header" title="AppHeader">
            <Label>Phone</Label>
            <div className="w-[390px] max-w-full">
              <AppHeader breadcrumb={["Tank T-04", "Point 3"]} saveStatus="SAVED 22:31" initials="MO" />
            </div>
            <Label>Desktop</Label>
            <div className="overflow-x-auto">
              <div className="w-[1024px]">
                <AppHeader breadcrumb={["Tank T-04", "Point 3"]} saveStatus="SAVED 22:31" initials="MO" current="inspections" />
              </div>
            </div>
          </Section>

          <Section id="bottom-bar" title="BottomBar">
            <div className="w-[390px] max-w-full pt-10">
              <BottomBar current="assets" reportsCount={2} />
            </div>
          </Section>
        </div>

        <footer className="border-t border-line pt-6 font-mono text-label text-muted uppercase">
          Screening only. Requires inspector sign-off.
        </footer>
      </main>
    </div>
  );
}
