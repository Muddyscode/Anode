// Anode grading rules (Phase 1). Every constant here was decided by Michael (D1, D2, D12).
// Changing any of them changes grades: bump GRADING_RULES_VERSION in the same change. Every
// stored AI finding records the version that graded it (domain model C12).

import riCutoffs from "./ri-cutoffs.json";
import type { DefectType, Severity } from "./types";

export const GRADING_RULES_VERSION = "2026-11-19.1";

export const STANDARD = { code: "ISO 4628-3", edition: "2016" } as const;

/**
 * D12: percent of area rusted to ISO 4628-3 Ri, rounding up. A measurement gets the lowest grade
 * whose published rusted area (D10) is at or above it, so Anode never under-grades.
 * Published values: Ri 0: 0%, Ri 1: 0.05%, Ri 2: 0.5%, Ri 3: 1%, Ri 4: 8%, Ri 5: 40 to 50%.
 * Kept in ri-cutoffs.json so the Python evaluation harness (model/) uses the same cut-offs.
 */
export const RI_UPPER_BOUND_PERCENT: readonly { ri: number; upTo: number }[] = riCutoffs.bands;

/** D12: Ri to severity, before defect floors, the low-confidence step-up and escalation. */
export const RI_SEVERITY: Readonly<Record<number, Severity>> = {
  0: "S1",
  1: "S1",
  2: "S2",
  3: "S2",
  4: "S3",
  5: "S4",
};

/** D12: the lowest severity a defect type can have. Pitting needs a thickness check; cracking is critical. */
export const DEFECT_SEVERITY_FLOOR: Readonly<Record<DefectType, Severity>> = {
  rusting: "S1",
  coating_breakdown: "S1",
  other: "S1",
  pitting: "S3",
  suspected_cracking: "S4",
};

/** D12: model confidence (0 to 1) to the finding's confidence. Re-tuned on the gold set in Stage 6. */
export const CONFIDENCE_THRESHOLDS = { high: 0.85, medium: 0.6 } as const;

/** C32: Phase 1 grades coated steel only. */
export const GRADEABLE_MATERIALS = ["carbon_steel", "low_alloy_steel", "galvanised_steel"] as const;
