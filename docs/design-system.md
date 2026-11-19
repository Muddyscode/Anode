# Design system: Galvanic Steel

Stage 4 of the Phase 1 build. The source is Michael's design system,
[Anode: Galvanic Steel](https://claude.ai/artifact/2yysQKathxmFxDts7L4xiA) (its README, `tokens.json`
and component guidelines). This repository implements it; it does not redesign it.

## Where things live

| Path | What |
|---|---|
| `design/tokens.json` | The tokens: colour (light and dark), type, spacing, radius, durations. The one source of truth in this repo |
| `design/anode-mark.svg`, `design/anode-mark-on-dark.svg` | The logo files, copied unchanged |
| `scripts/build-tokens.mjs` | Generates `app/tokens.css` from the tokens (`npm run tokens`) |
| `app/tokens.css` | Generated: CSS variables for light and dark, and the Tailwind theme |
| `app/globals.css` | Brushed grain, the four motions and their reduced-motion fallbacks |
| `components/ds/` | The seven components: `AppHeader`, `BottomBar`, `Button`, `Nameplate`, `PhotoFrame`, `SeverityGauge`, `SeverityMarker` |
| `design/color.ts` | Contrast and colour-blindness checks used by the tests and the `/design` page |
| `app/design/` | The `/design` page: every token and component, in light and dark |

## How the rules are enforced

| Rule | Enforced by |
|---|---|
| No colour outside the system | The Tailwind theme replaces all default colours, radii, fonts and text sizes, so `bg-red-500` does not exist. A test fails on any literal colour in `app/` or `components/`, except the photo-overlay colours copied from the PhotoFrame preview. |
| Tokens and CSS never drift | A test regenerates `app/tokens.css` and fails if the committed file differs. |
| Text contrast 4.5:1, control borders and focus 3:1, in both themes | `design/tokens.test.ts` checks every pair the system names; axe checks the rendered `/design` page in both themes (Playwright). |
| Severity colours distinct for colour-blind users | Every pair of `sev-1` to `sev-4` differs by at least ΔE 15 under typical vision, protanopia, deuteranopia and tritanopia (D11). |
| Reduced motion | Under `prefers-reduced-motion`, every animation stops and shows its final state; checked in the browser. |
| Component guidelines | `components/ds/components.test.tsx` checks the code, name and action on every marker; needle angles; nameplate accessible value; disabled reason; rejected-photo state; breadcrumb; count plate. |

## Theme

Light and dark follow the device (`prefers-color-scheme`). Setting `data-theme="light"` or
`data-theme="dark"` on `<html>` overrides it. Severity colours are the same in both themes.

## Motion

| Moment | Class | Token |
|---|---|---|
| Corrosion outline draws on | `ds-outline-draw` | `dur-outline` |
| Pulse laps the outline while measuring | `ds-outline-pulse` | `dur-pulse` |
| Gauge needle sweeps, overshoots once, settles | `ds-needle` | `dur-needle` |
| Severity marker slides in | `ds-marker-in` | `dur-marker` |
| Button press nudge (80ms, from the Button guidelines) | `ds-press` | |

## Changes from the source design system

All approved by Michael on 19 Nov 2026 (D11), and applied to the source design system too:

- `sev-1` `#1E6B45` → `#1A5B3B`, `sev-2` `#D9A21B` → `#E4AC25`, `sev-4` `#D73A2F` → `#D33429`,
  so the four severities stay distinct for colour-blind users (closest pair ΔE 11.1 → 15.2).
- `line-strong` light `#7B8794` → `#74818E`, dark `#5B6B82` → `#5D6D85`, so control borders reach
  3:1 on the brushed-zinc panel.

## Built from guidelines without a preview

The desktop `AppHeader` (wordmark, section links, search field, `New inspection`) has guidelines but no
preview in the source. It uses only the system's tokens and components; its search field uses
`line-strong` for the border, as the token's usage note says for inputs.

## Running it

```sh
npm run dev          # http://localhost:3000/design
npm run tokens       # after editing design/tokens.json
npm test             # contracts, tokens, components
npm run build && npm run e2e   # browser checks: axe in both themes, motion
```
