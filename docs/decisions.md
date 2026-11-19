# Decisions and stage instructions

A running log of Michael's decisions and instructions, so each build stage starts from what was agreed.
Newest at the bottom of each section.

## Working agreement

- Claude Code works one stage at a time and stops for Michael's approval at the end of each (PRD, "Build stages").
- **One pull request per stage**, into `main`, from a branch cut from the latest `main`. A stage does not start until the previous stage's pull request is approved.
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

## Stage 2: Database (merged 19 Nov 2026)

Merged through #2 and #3. No new decisions; refinements are in [`domain-model.md` §14](domain-model.md#14-implementation-notes-stage-2).

## Stage 3: API contracts (decision given 19 Nov 2026)

- **D10: no paid standards; the AI is the only paid service.** Anode does not buy ISO 4628-3 or any
  other standard. The Ri grade is computed from the percentage of rusted area using the published
  Ri-to-percentage values (Ri 0: 0%, Ri 1: 0.05%, Ri 2: 0.5%, Ri 3: 1%, Ri 4: 8%, Ri 5: 40 to 50%),
  cited by standard and edition with their source; the standard's pictorial references are never
  copied or needed. Michael checks the values as the domain expert. Everything else runs on free
  tiers (Supabase, Vercel Hobby, Google Colab); the Claude API for the explain step is the only paid
  item. This supersedes the PRD's "buying the current editions ... is a project cost" and "buy
  ISO 4628-3 first".

## Stage 3: API contracts (merged 19 Nov 2026)

Merged through #4.

## Stage 4: Design system (instructions given 18 Nov 2026; decision 19 Nov 2026)

- **D11: severity and border colours adjusted for accessibility.** Checking the design system's
  tokens showed that S1 and S4 look almost alike to red-blind users and S2 and S3 are close for
  green-blind users, and that `line-strong` on `panel` was under 3:1. Michael approved:
  `sev-1` `#1A5B3B`, `sev-2` `#E4AC25`, `sev-4` `#D33429` (S3 unchanged), and `line-strong`
  `#74818E` light, `#5D6D85` dark. Every pair of severity colours now differs by at least ΔE 15
  under typical vision, protanopia, deuteranopia and tritanopia, and a test keeps it that way.


- Implement the design system from https://claude.ai/artifact/2yysQKathxmFxDts7L4xiA.
- Read its README first, then `tokens.json`, then each component's guidelines.
- Turn the tokens into Tailwind theme values and CSS variables for light and dark.
- Build the seven components exactly as specified, with their animations and reduced-motion fallbacks.
- Add a `/design` page that shows them all.
- Do not invent any colours or components that are not in the system; ask Michael first.
- Implemented in [`design-system.md`](design-system.md).

## Stage 4: Design system (merged 19 Nov 2026)

Merged through #5. The source design system was updated with the D11 colours.

## Stage 5: Grading engine (decisions given 19 Nov 2026)

- **D12: grading rules.** Recorded in [`grading.md`](grading.md) and `lib/grading/rules.ts`:
  - Percent rusted to Ri rounds up to the next published ISO 4628-3 value (0; 0.05; 0.5; 1; 8;
    above 8 is Ri 5), so Anode never under-grades.
  - Ri 0 to 1 is S1, Ri 2 to 3 is S2, Ri 4 is S3, Ri 5 is S4.
  - Pitting is at least S3; suspected cracking is S4.
  - Model confidence 0.85 or more is high, 0.60 or more is medium, below is low; to be
    recalibrated on the gold set in Stage 6.
- The recommendation library and context questions are a first draft for Michael to correct (D5).

## Stage 5: Grading engine (merged 19 Nov 2026)

Merged through #6.

## Stage 6: Measurement model (decisions given 19 Nov 2026)

- **D13: how Stage 6 runs.** Split into 6a (Colab notebook, model API, evaluation harness, results
  on a held-out public test set) and 6b (the same harness on Michael's gold set once labelled).
  Model: U-Net from segmentation_models_pytorch (MIT) with a ResNet-18 encoder. Hosting: a free
  Hugging Face Space (CPU). Training data: only datasets under CC BY 4.0 or more permissive, with
  attribution in `model/ATTRIBUTION.md`.

