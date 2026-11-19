// Component guidelines that code can check (Galvanic Steel component READMEs).
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { AppHeader, BottomBar, Button, Nameplate, PhotoFrame, SEVERITIES, SeverityGauge, SeverityMarker } from "./index";

const html = (el: React.ReactElement) => renderToStaticMarkup(el);

describe("SeverityMarker", () => {
  it.each(SEVERITIES)("%s always prints its code, name and action", (s) => {
    const out = html(<SeverityMarker severity={s} />);
    expect(out).toContain(`>${s}<`);
    expect(out).toMatch(/Cosmetic|Developing|Significant|Critical/);
    expect(out).toContain(`aria-label="Severity ${s},`);
    expect(out).toContain("clip-path:polygon(0 0, calc(100% - 22px) 0, 100% 50%");
  });
  it("slides in unless animation is off", () => {
    expect(html(<SeverityMarker severity="S2" />)).toContain("ds-marker-in");
    expect(html(<SeverityMarker severity="S2" animate={false} />)).not.toContain("ds-marker-in");
  });
});

describe("SeverityGauge", () => {
  it.each([
    ["S1", "22.5deg"],
    ["S2", "67.5deg"],
    ["S3", "112.5deg"],
    ["S4", "157.5deg"],
  ] as const)("%s points the needle at %s and states the reading", (s, angle) => {
    const out = html(<SeverityGauge severity={s} confidence="high" />);
    expect(out).toContain(`--needle-angle:${angle}`);
    expect(out).toContain(`aria-label="Severity gauge reading ${s}`);
    expect(out).toContain("Confidence high");
  });
});

describe("Nameplate", () => {
  it("gives the grade as its accessible value; rivets are decorative", () => {
    const out = html(<Nameplate standard="ISO 4628-3" grade={3} percentRusted={1.02} />);
    expect(out).toContain('aria-label="Grade Ri 3, 1.02 percent rusted, ISO 4628-3"');
    expect(out.match(/aria-hidden="true" class="absolute size-\[5px\]/g)).toHaveLength(4);
    expect(out).toContain("1.02% RUSTED");
  });
});

describe("Button", () => {
  it("is 48px tall with the press nudge", () => {
    expect(html(<Button>Sign finding</Button>)).toMatch(/class="ds-press h-12 rounded-md/);
  });
  it("a disabled button shows and links its reason", () => {
    const out = html(<Button disabled disabledReason="Add a scale card to grade">Grade photo</Button>);
    const id = /aria-describedby="([^"]+)"/.exec(out)?.[1];
    expect(id).toBeTruthy();
    expect(out).toContain(`id="${id}"`);
    expect(out).toContain("Add a scale card to grade");
  });
  it("escalate uses the sev-4 border and danger text", () => {
    expect(html(<Button variant="escalate">Escalate to inspector</Button>)).toContain("border-sev-4 bg-transparent text-danger-text");
  });
});

describe("PhotoFrame", () => {
  const outline = [[[[0, 0], [10, 0], [10, 10], [0, 0]]]];
  it("draws the outline when measured, with no pulse", () => {
    const out = html(<PhotoFrame alt="a" widthPx={100} heightPx={50} outline={outline} state="measured" caption="c" scaleLabel="ANODE SCALE 50 MM" />);
    expect(out).toContain('d="M0 0 L10 0 L10 10 L0 0 Z"');
    expect(out).toContain("ds-outline-draw");
    expect(out).not.toContain("ds-outline-pulse");
    expect(out).toContain("ANODE SCALE 50 MM");
    expect(out.match(/border-photo-mark/g)).toHaveLength(4);
  });
  it("pulses while measuring", () => {
    expect(html(<PhotoFrame alt="a" widthPx={100} heightPx={50} outline={outline} state="measuring" caption="c" />)).toContain("ds-outline-pulse");
  });
  it("a rejected photo shows no outline, only the reason and Retake", () => {
    const out = html(<PhotoFrame alt="a" widthPx={100} heightPx={50} outline={outline} state="rejected" caption="c" scaleLabel="X" rejectionReason="No scale reference found" />);
    expect(out).not.toContain("<path");
    expect(out).not.toContain(">X<");
    expect(out).toContain('role="alert"');
    expect(out).toContain("No scale reference found");
    expect(out).toContain("Retake photo");
  });
});

describe("AppHeader and BottomBar", () => {
  it("the header marks the current breadcrumb level", () => {
    const out = html(<AppHeader breadcrumb={["Tank T-04", "Point 3"]} saveStatus="SAVED 22:31" initials="MO" />);
    expect(out).toContain('aria-current="page">Point 3<');
    expect(out).toContain("SAVED 22:31");
    expect(out).toContain('aria-label="Account menu"');
  });
  it("hides the reports count plate at zero", () => {
    expect(html(<BottomBar reportsCount={0} />)).not.toContain("bg-ink");
    expect(html(<BottomBar reportsCount={2} />)).toContain("Reports, 2 waiting for sign-off");
  });
  it("capture is a raised cobalt square", () => {
    expect(html(<BottomBar reportsCount={0} />)).toMatch(/aria-label="Capture"[^>]*class="-mt-\[26px\] flex size-\[60px\][^"]*bg-cobalt/);
  });
});
