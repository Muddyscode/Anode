# Decisions and stage instructions

A running log of Michael's decisions and instructions, so each build stage starts from what was agreed.
Newest at the bottom of each section.

## Working agreement

- Claude Code works one stage at a time and stops for Michael's approval at the end of each (PRD, "Build stages").
- **One pull request per stage**, into `main`. A stage does not start until the previous stage's pull request is approved.
- Every stage ends with tests passing, no lint errors, and a short report of what changed and which assumptions were made.

## Stage 1: Domain model (approved 18 Nov 2026)

Recorded in full in [`domain-model.md`, section 13](domain-model.md#13-decisions), D1 to D9:

- D1: low confidence raises severity one step at every level, capped at S4.
- D2: every finding on an injury-risk asset escalates, even S1 (Phase 1; tune after real use).
- D3: rule 4 applies only to AI findings; a qualified inspector may set S1 with a reason.
- D4: medium confidence does not block S1; only low does.
- D5: Claude drafts the recommendation library and context questions in Stage 5; Michael corrects them.
- D6: scale references: printed Anode scale card preferred; ruler or tape measure accepted; coins not accepted.
- D7: void and reissue in Phase 1; signed reports are never edited or deleted.
- D8: append-only audit log in Phase 1 (signing, voiding, escalation acknowledgements, finding edits).
- D9: D610 deferred; Phase 1 is ISO 4628-3 only; assumptions A1 to A35 accepted.

## Stage 4: Design system (instructions given 18 Nov 2026)

- Implement the design system from https://claude.ai/artifact/2yysQKathxmFxDts7L4xiA.
- Read its README first, then `tokens.json`, then each component's guidelines.
- Turn the tokens into Tailwind theme values and CSS variables for light and dark.
- Build the seven components exactly as specified, with their animations and reduced-motion fallbacks.
- Add a `/design` page that shows them all.
- Do not invent any colours or components that are not in the system; ask Michael first.
