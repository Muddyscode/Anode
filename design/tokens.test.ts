// The design system's own rules, checked by code (Stage 4 definition of done).
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, expect, it } from "vitest";
import { buildTokensCss, readTokens } from "../scripts/build-tokens.mjs";
import { COLORS, CONTRAST_PAIRS, MIN_SEVERITY_DELTA_E, VISIONS, colorOf, contrast, deltaE, type Theme } from "./color";

const ROOT = join(__dirname, "..");
const THEMES: Theme[] = ["light", "dark"];

describe("tokens", () => {
  it("app/tokens.css is generated from design/tokens.json (run npm run tokens)", () => {
    expect(readFileSync(join(ROOT, "app/tokens.css"), "utf8")).toBe(buildTokensCss(readTokens()));
  });

  it("every colour has a valid hex value in both themes and a usage note", () => {
    for (const c of COLORS) {
      for (const t of THEMES) expect(c.value[t], `${c.name} ${t}`).toMatch(/^#[0-9A-Fa-f]{6}$/);
      expect(c.usage.length, c.name).toBeGreaterThan(10);
    }
  });

  it("names are unique", () => {
    const names = COLORS.map((c) => c.name);
    expect(new Set(names).size).toBe(names.length);
  });

  it("the Tailwind theme contains only the system's colours", () => {
    const css = readFileSync(join(ROOT, "app/tokens.css"), "utf8");
    expect(css).toContain("--color-*: initial;");
    const themeColours = [...css.matchAll(/--color-([a-z0-9-]+): var/g)].map((m) => m[1]);
    expect(themeColours.sort()).toEqual(COLORS.map((c) => c.name).sort());
  });
});

describe("WCAG AA contrast in every theme", () => {
  for (const theme of THEMES) {
    it.each(CONTRAST_PAIRS)(`${theme}: $fg on $bg is at least $min:1 ($why)`, ({ fg, bg, min }) => {
      expect(contrast(colorOf(fg, theme), colorOf(bg, theme))).toBeGreaterThanOrEqual(min);
    });
  }
});

describe("severity colours are distinct for colour-blind users (D11)", () => {
  const sev = ["sev-1", "sev-2", "sev-3", "sev-4"];
  for (const vision of VISIONS) {
    for (let i = 0; i < sev.length; i++) {
      for (let j = i + 1; j < sev.length; j++) {
        const [a, b] = [sev[i]!, sev[j]!];
        it(`${vision}: ${a} and ${b} differ by at least ΔE ${MIN_SEVERITY_DELTA_E}`, () => {
          expect(deltaE(colorOf(a, "light"), colorOf(b, "light"), vision)).toBeGreaterThanOrEqual(MIN_SEVERITY_DELTA_E);
        });
      }
    }
  }

  it("severity colours are the same in both themes", () => {
    for (const s of sev) expect(colorOf(s, "dark")).toBe(colorOf(s, "light"));
  });
});

describe("no colours outside the system", () => {
  // Literal colours are allowed only where the design system's own preview uses them on a photo.
  const ALLOWED: Record<string, string[]> = {
    "components/ds/PhotoFrame.tsx": ["#6B4A36", "#F6F7F9", "#0E1420", "rgba(14, 20, 32, 0.72)", "#FFFFFF"],
  };
  const COLOUR = /#[0-9A-Fa-f]{3,8}\b|rgba?\([^)]*\)|hsla?\([^)]*\)/g;

  function files(dir: string): string[] {
    return readdirSync(join(ROOT, dir)).flatMap((f) => {
      const p = join(dir, f);
      if (statSync(join(ROOT, p)).isDirectory()) return files(p);
      return /\.(tsx?|css)$/.test(f) && !f.endsWith(".test.ts") && !f.endsWith(".test.tsx") && f !== "tokens.css" ? [p] : [];
    });
  }

  const sources = [...files("app"), ...files("components")];

  it("finds the source files", () => {
    expect(sources.length).toBeGreaterThan(5);
  });

  it.each(sources)("%s uses only token colours", (file) => {
    const text = readFileSync(join(ROOT, file), "utf8");
    const found = (text.match(COLOUR) ?? []).filter((c) => !(ALLOWED[relative(ROOT, join(ROOT, file))] ?? []).includes(c));
    // The grain gradient uses white and black at token-set strengths, as the README specifies.
    const grain = found.filter((c) => !/^rgba\((255, 255, 255|0, 0, 0), (var\(--grain-[ld]|0)/.test(c));
    expect(grain).toEqual([]);
  });
});
