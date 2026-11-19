// Generates app/tokens.css from design/tokens.json (the Galvanic Steel design system).
//
//   npm run tokens          write app/tokens.css
//   buildTokensCss(tokens)  the same output, for the test that keeps the file current
//
// Output layers:
//   1. Raw CSS variables (--ground, --space-4, --dur-needle, ...) for light, and for dark under
//      prefers-color-scheme or data-theme="dark". Components and plain CSS use these.
//   2. A Tailwind @theme that REPLACES Tailwind's default colours, radii, fonts and text sizes
//      with the system's, so a colour outside the system cannot be written as a class.

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");

/** Brushed grain strengths, from the design system README ("Materials"). */
const GRAIN = { light: { l: "0.5", d: "0.035" }, dark: { l: "0.035", d: "0.18" } };

/** Fonts loaded with next/font expose a CSS variable; fall back to the family name. */
const FONT_VARIABLES = { "Space Grotesk": "--font-space-grotesk", "JetBrains Mono": "--font-jetbrains-mono" };

function fontStack(stack) {
  return stack.replace(/"([^"]+)"/g, (whole, name) =>
    FONT_VARIABLES[name] ? `var(${FONT_VARIABLES[name]}, "${name}")` : whole,
  );
}

function colorBlock(tokens, theme, indent) {
  return tokens.map((t) => `${indent}--${t.name}: ${t.value[theme] ?? t.value.light};`).join("\n");
}

export function buildTokensCss(tokens) {
  const colors = tokens.color.tokens;
  const spacing = tokens.spacing.tokens;
  const radius = tokens.radius.tokens;
  const durations = tokens.duration.tokens;
  const styles = tokens.type.groups.flatMap((g) => g.styles.map((s) => ({ ...s, family: g.family })));

  const lines = [];
  lines.push(`/* ${tokens.name} v${tokens.version}: generated from design/tokens.json by scripts/build-tokens.mjs. Do not edit; run npm run tokens. */`);
  lines.push("");
  lines.push(`:root,\n[data-theme="light"] {\n  color-scheme: light;`);
  lines.push(colorBlock(colors, "light", "  "));
  lines.push(`  --grain-l: ${GRAIN.light.l};\n  --grain-d: ${GRAIN.light.d};`);
  lines.push(spacing.map((t) => `  --${t.name}: ${t.value};`).join("\n"));
  lines.push(durations.map((t) => `  --${t.name}: ${t.value};`).join("\n"));
  lines.push("}");
  lines.push("");
  const dark = `  color-scheme: dark;\n${colorBlock(colors, "dark", "  ")}\n  --grain-l: ${GRAIN.dark.l};\n  --grain-d: ${GRAIN.dark.d};`;
  lines.push(`@media (prefers-color-scheme: dark) {\n  :root:not([data-theme="light"]) {\n${dark.replace(/^/gm, "  ")}\n  }\n}`);
  lines.push("");
  lines.push(`[data-theme="dark"] {\n${dark}\n}`);
  lines.push("");
  lines.push("@theme inline {");
  lines.push("  --color-*: initial;");
  lines.push(colors.map((t) => `  --color-${t.name}: var(--${t.name});`).join("\n"));
  lines.push("}");
  lines.push("");
  lines.push("@theme {");
  lines.push("  --radius-*: initial;");
  lines.push(radius.map((t) => `  --radius-${t.name.replace(/^radius-/, "")}: ${t.value};`).join("\n"));
  lines.push("  --font-*: initial;");
  lines.push(Object.entries(tokens.type.families).map(([k, v]) => `  --font-${k}: ${fontStack(v)};`).join("\n"));
  lines.push("  --text-*: initial;");
  for (const s of styles) {
    lines.push(`  --text-${s.name}: ${s.fontSize};`);
    lines.push(`  --text-${s.name}--line-height: ${s.lineHeight};`);
    lines.push(`  --text-${s.name}--font-weight: ${s.fontWeight};`);
    if (s.letterSpacing) lines.push(`  --text-${s.name}--letter-spacing: ${s.letterSpacing};`);
  }
  lines.push("}");
  return lines.join("\n") + "\n";
}

export function readTokens() {
  return JSON.parse(readFileSync(join(ROOT, "design", "tokens.json"), "utf8"));
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  writeFileSync(join(ROOT, "app", "tokens.css"), buildTokensCss(readTokens()));
  console.log("wrote app/tokens.css");
}
