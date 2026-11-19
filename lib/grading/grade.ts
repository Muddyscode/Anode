// The grading engine: measurement in, grade out. Plain functions, no AI, no I/O, no clock, so the
// same numbers always give the same grade (PRD, "AI approach": step 2).

import type { z } from "zod";
import { expectedAiSeverity, severityRank } from "@/contracts/common";
import { AiGrade as AiGradeSchema } from "@/contracts/findings";
import {
  CONFIDENCE_THRESHOLDS,
  DEFECT_SEVERITY_FLOOR,
  GRADEABLE_MATERIALS,
  GRADING_RULES_VERSION,
  RI_SEVERITY,
  RI_UPPER_BOUND_PERCENT,
  STANDARD,
} from "./rules";
import type { AssetFacts, ConfidenceLevel, DefectType, Escalation, Severity } from "./types";

export type AiGrade = z.infer<typeof AiGradeSchema>;

/** D12: ISO 4628-3 Ri for a percent of area rusted, rounding up. */
export function riFromPercent(percentAreaRusted: number): number {
  if (!Number.isFinite(percentAreaRusted) || percentAreaRusted < 0 || percentAreaRusted > 100) {
    throw new RangeError(`percent of area rusted must be 0 to 100, got ${percentAreaRusted}`);
  }
  const band = RI_UPPER_BOUND_PERCENT.find((b) => percentAreaRusted <= b.upTo);
  // The last band is up to 100%, which the range check above guarantees.
  return band!.ri;
}

/** D12: the finding's confidence from the model's score. */
export function confidenceFromScore(modelConfidence: number): ConfidenceLevel {
  if (!Number.isFinite(modelConfidence) || modelConfidence < 0 || modelConfidence > 1) {
    throw new RangeError(`model confidence must be 0 to 1, got ${modelConfidence}`);
  }
  if (modelConfidence >= CONFIDENCE_THRESHOLDS.high) return "high";
  if (modelConfidence >= CONFIDENCE_THRESHOLDS.medium) return "medium";
  return "low";
}

const higher = (a: Severity, b: Severity): Severity => (severityRank(a) >= severityRank(b) ? a : b);

/** D12: severity from the grade and the defect type, before the low-confidence step-up. */
export function rulesSeverity(ri: number, defectType: DefectType): Severity {
  const fromGrade = RI_SEVERITY[ri];
  if (fromGrade === undefined) throw new RangeError(`Ri must be 0 to 5, got ${ri}`);
  return higher(fromGrade, DEFECT_SEVERITY_FLOOR[defectType]);
}

export interface GradeInput {
  percentAreaRusted: number;
  modelConfidence: number;
  defectType: DefectType;
}

/**
 * Grades one measurement. The result always parses as the AiGrade contract, so it obeys D1 and D4
 * the same way the database does: low confidence raises the severity one step, capped at S4, and says why.
 */
export function gradeMeasurement(input: GradeInput): AiGrade {
  const gradeValue = riFromPercent(input.percentAreaRusted);
  const confidence = confidenceFromScore(input.modelConfidence);
  const base = rulesSeverity(gradeValue, input.defectType);
  const severity = expectedAiSeverity(base, confidence);
  const raised = severity !== base;
  return AiGradeSchema.parse({
    standardCode: STANDARD.code,
    gradeValue,
    rulesSeverity: base,
    severity,
    confidence,
    severityRaisedReason: raised
      ? `Model confidence is low, so severity was raised from ${base} to ${severity} (rule 4).`
      : null,
    defectType: input.defectType,
    gradingRulesVersion: GRADING_RULES_VERSION,
  });
}

/** C32: whether Phase 1 can grade this asset, and why not. */
export function checkScope(asset: Pick<AssetFacts, "material" | "coatingStatus">): { ok: true } | { ok: false; reason: string } {
  if (!(GRADEABLE_MATERIALS as readonly string[]).includes(asset.material)) {
    return { ok: false, reason: "Phase 1 grades steel only (carbon, low-alloy or galvanised)." };
  }
  if (asset.coatingStatus !== "coated") {
    return { ok: false, reason: "Phase 1 grades coated steel only, on ISO 4628-3." };
  }
  return { ok: true };
}

/**
 * Rule 5 (and D2): the escalations a finding must carry. The database adds the same ones by
 * trigger (domain model §14); this function lets the app show them before anything is stored.
 */
export function requiredEscalations(args: {
  severity: Severity;
  defectType: DefectType;
  asset: Pick<AssetFacts, "isInsulated" | "isPressureContaining" | "failureCouldInjure">;
  rankedMechanisms?: readonly string[];
}): Escalation[] {
  const { severity, defectType, asset } = args;
  const mechanisms = args.rankedMechanisms ?? [];
  const out = new Set<Escalation>();
  if (severity === "S4") out.add("severity_s4");
  if (asset.failureCouldInjure) out.add("injury_risk");
  if (asset.isInsulated || mechanisms.includes("cui")) out.add("suspected_cui");
  if (asset.isPressureContaining && (defectType === "pitting" || mechanisms.includes("pitting"))) {
    out.add("pressure_pitting_or_wall_loss");
  }
  if (defectType === "suspected_cracking") out.add("suspected_cracking");
  return [...out];
}
