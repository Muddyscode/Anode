// Colour checks for the design system: WCAG contrast and colour-vision-deficiency separation.
// Used by the /design page (to show the numbers) and by design/tokens.test.ts (to enforce them).

import tokensJson from "./tokens.json";

export type Theme = "light" | "dark";
export interface ColorToken {
  name: string;
  value: Record<Theme, string>;
  usage: string;
}

export const tokens = tokensJson;
export const COLORS: ColorToken[] = tokensJson.color.tokens as ColorToken[];

export function colorOf(name: string, theme: Theme): string {
  const t = COLORS.find((c) => c.name === name);
  if (!t) throw new Error(`unknown colour token ${name}`);
  return t.value[theme] ?? t.value.light;
}

function channels(hex: string): [number, number, number] {
  const h = hex.replace("#", "");
  return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16) / 255) as [number, number, number];
}

const linear = (c: number) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);

export function luminance(hex: string): number {
  const [r, g, b] = channels(hex).map(linear) as [number, number, number];
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/** WCAG 2.x contrast ratio. */
export function contrast(a: string, b: string): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x) as [number, number];
  return (hi + 0.05) / (lo + 0.05);
}

/**
 * Pairs the design system says must be readable, with the WCAG minimum for each:
 * 4.5 for text, 3 for control borders, focus rings and large or non-text marks.
 */
export const CONTRAST_PAIRS: { fg: string; bg: string; min: number; why: string }[] = [
  ...["ground", "surface", "panel"].flatMap((bg) => [
    { fg: "ink", bg, min: 4.5, why: "Primary text" },
    { fg: "muted", bg, min: 4.5, why: "Secondary text and mono labels" },
    { fg: "line-strong", bg, min: 3, why: "Control borders" },
    { fg: "cobalt", bg, min: 3, why: "Focus ring" },
  ]),
  { fg: "link", bg: "ground", min: 4.5, why: "Text links" },
  { fg: "link", bg: "surface", min: 4.5, why: "Text links" },
  { fg: "danger-text", bg: "ground", min: 4.5, why: "Escalate label and errors" },
  { fg: "danger-text", bg: "surface", min: 4.5, why: "Escalate label and errors" },
  { fg: "sev-4", bg: "ground", min: 3, why: "Escalate button border" },
  { fg: "on-cobalt", bg: "cobalt", min: 4.5, why: "Primary button and capture button" },
  { fg: "ground", bg: "ink", min: 4.5, why: "Count plate" },
  { fg: "on-sev-1", bg: "sev-1", min: 4.5, why: "S1 marker text" },
  { fg: "on-sev-2", bg: "sev-2", min: 4.5, why: "S2 marker text" },
  { fg: "on-sev-3", bg: "sev-3", min: 4.5, why: "S3 marker text" },
  { fg: "on-sev-4", bg: "sev-4", min: 4.5, why: "S4 marker text" },
];

// Colour-vision deficiency simulation (Machado, Oliveira and Fernandes 2009, severity 1.0),
// applied in linear RGB, compared in CIELAB (D65).

export type Vision = "typical" | "protanopia" | "deuteranopia" | "tritanopia";
const MATRIX: Record<Exclude<Vision, "typical">, number[][]> = {
  protanopia: [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
  deuteranopia: [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.01182, 0.04294, 0.968881]],
  tritanopia: [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.3039]],
};

function toLab([r, g, b]: number[]): [number, number, number] {
  const x = (0.4124 * r! + 0.3576 * g! + 0.1805 * b!) / 0.95047;
  const y = 0.2126 * r! + 0.7152 * g! + 0.0722 * b!;
  const z = (0.0193 * r! + 0.1192 * g! + 0.9505 * b!) / 1.08883;
  const f = (v: number) => (v > 0.008856 ? Math.cbrt(v) : 7.787 * v + 16 / 116);
  return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))];
}

export function labAs(hex: string, vision: Vision): [number, number, number] {
  const rgb = channels(hex).map(linear);
  if (vision === "typical") return toLab(rgb);
  const m = MATRIX[vision];
  return toLab(m.map((row) => Math.min(1, Math.max(0, row[0]! * rgb[0]! + row[1]! * rgb[1]! + row[2]! * rgb[2]!))));
}

/** CIE76 colour difference between two colours as a person with this vision sees them. */
export function deltaE(a: string, b: string, vision: Vision): number {
  const [l1, a1, b1] = labAs(a, vision);
  const [l2, a2, b2] = labAs(b, vision);
  return Math.hypot(l1 - l2, a1 - a2, b1 - b2);
}

export const VISIONS: Vision[] = ["typical", "protanopia", "deuteranopia", "tritanopia"];

/** Minimum separation between any two severity colours for every vision type (decision D11). */
export const MIN_SEVERITY_DELTA_E = 15;
