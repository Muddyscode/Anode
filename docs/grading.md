# Grading engine

Stage 5 of the Phase 1 build: step 2 of the pipeline ("Grade"). Plain code in
[`lib/grading/`](../lib/grading): no AI, no I/O, no clock, so the same measurement always gives
the same grade. Every rule here was decided by Michael (D1, D2, D10, D12) and lives in
[`lib/grading/rules.ts`](../lib/grading/rules.ts) as named constants.

## From measurement to grade

| Step | Rule | Decision |
|---|---|---|
| 1. Percent rusted → Ri | Round up to the next published ISO 4628-3 value | D10, D12 |
| 2. Ri → severity | Ri 0 to 1 → S1, Ri 2 to 3 → S2, Ri 4 → S3, Ri 5 → S4 | D12 |
| 3. Defect floor | Pitting is at least S3; suspected cracking is S4 | D12 |
| 4. Model score → confidence | 0.85 or more high, 0.60 or more medium, below 0.60 low | D12 |
| 5. Low confidence | Raise the severity one step, capped at S4, and say why | D1, D4, R4 |
| 6. Escalation | S4, injury-risk asset (any severity), insulated asset or CUI ranked, pitting on pressure equipment, suspected cracking | R5, D2 |

### Percent rusted to Ri (rounding up)

| Percent of area rusted | Ri | Published value (D10) |
|---|---|---|
| 0 | 0 | 0% |
| above 0, up to 0.05 | 1 | 0.05% |
| above 0.05, up to 0.5 | 2 | 0.5% |
| above 0.5, up to 1 | 3 | 1% |
| above 1, up to 8 | 4 | 8% |
| above 8 | 5 | 40 to 50% |

A measurement gets the lowest grade whose published value is at or above it, so Anode never
under-grades. The published values come from ISO 4628-3:2016 as widely reproduced (D10).

## Functions

| Function | Does |
|---|---|
| `riFromPercent(pct)` | Step 1. Refuses values outside 0 to 100 |
| `confidenceFromScore(score)` | Step 4. Refuses values outside 0 to 1 |
| `rulesSeverity(ri, defectType)` | Steps 2 and 3 |
| `gradeMeasurement({ percentAreaRusted, modelConfidence, defectType })` | All of the above; returns an `AiGrade` (contract) with `gradingRulesVersion` |
| `checkScope(asset)` | C32: coated carbon, low-alloy or galvanised steel only |
| `requiredEscalations({ severity, defectType, asset, rankedMechanisms })` | Step 6, matching the database triggers |

## Versioning

`GRADING_RULES_VERSION` (now `2026-11-19.1`) is stored on every AI finding. Any change to a rule
in `rules.ts` must bump it, so old findings stay explainable. The confidence thresholds are a
starting point and will be recalibrated on the gold set in Stage 6.

## Tests

`lib/grading/grade.test.ts` checks every boundary value (each cut-off and a hair above it), every
Ri and defect combination, the low-confidence step-up at every level, every escalation rule and
every scope case. The build fails below 100% statement, branch, function and line coverage on
this module (Stage 5 definition of done).

## Draft recommendation library and context questions (D5)

[`supabase/migrations/20261119000100_draft_library.sql`](../supabase/migrations/20261119000100_draft_library.sql)
holds the first draft: 14 recommendations and 8 context questions. Michael corrects them as the
domain expert; a corrected wording becomes version 2 of that recommendation, never an edit.

| Recommendation | Offered from |
|---|---|
| Monitor at the normal interval | any |
| Re-inspect sooner | S2 |
| Spot-repair the coating | S2 |
| Plan coating maintenance | S2 |
| UT thickness grid | S3 |
| Measure pit depth | S3 |
| Check for cracking (dye-penetrant or MPI) | any |
| Remove insulation and inspect | any |
| Check for dissimilar-metal contact | any |
| Seal the joint or crevice | any |
| Improve drainage | any |
| Sample deposits for microbiological testing | any |
| Confirm it is rust, not staining | any |
| Refer to a qualified inspector now | S4 |

Context questions: exposure; coating condition; standing water; joint or crevice; contact with a
different metal; slimy or nodular deposits; possible staining source; years since last coated.
