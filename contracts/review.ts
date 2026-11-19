// Review, revision and escalation actions (domain model E15 to E20; R5, R9, D3, D7).

import { z } from "zod";
import { Confidence, DefectType, EscalationReason, NonBlank, Severity, Uuid } from "./common";
import { Escalation, Finding } from "./findings";

/** An inspector's own finding: their judgement, so no rule adjustment applies (D3). */
export const InspectorFindingFields = z.strictObject({
  defectType: DefectType,
  /** ISO 4628-3 Ri, 0 to 5 (C13). */
  gradeValue: z.number().int().min(0).max(5),
  /** Any level, S1 included, even when the AI's confidence was low (D3). */
  severity: Severity,
  confidence: Confidence,
  possibleStaining: z.boolean().default(false),
  summary: NonBlank(1500),
  /** Up to three ranked mechanisms, first is most likely (R7). */
  hypotheses: z
    .array(z.strictObject({ mechanismCode: z.string().min(1), visualEvidence: NonBlank(1000), evidenceAnswerIds: z.array(Uuid).max(10).default([]) }))
    .max(3)
    .default([]),
  /** Library codes only (R8). */
  recommendationCodes: z.array(z.string().min(1)).max(5).default([]),
});

// reviewFinding --------------------------------------------------------------------------
/**
 * The inspector's decision on a draft AI finding (R9). Done in one database transaction:
 * an edit writes the inspector's finding and the review together.
 */
export const ReviewFindingInput = z.discriminatedUnion("decision", [
  z.strictObject({ findingId: Uuid, decision: z.literal("accept") }),
  z.strictObject({ findingId: Uuid, decision: z.literal("reject"), reason: NonBlank(1000) }),
  z.strictObject({ findingId: Uuid, decision: z.literal("edit"), reason: NonBlank(1000), revision: InspectorFindingFields }),
]);
export const ReviewFindingOutput = z.strictObject({
  /** The reviewed AI finding, now accepted, rejected or superseded. */
  finding: Finding,
  /** The inspector's finding, when the decision was an edit. */
  revision: Finding.nullable(),
  inspectionStatus: z.enum(["draft", "ready_for_signoff"]),
});

// addInspectorFinding -----------------------------------------------------------------
/** A finding the AI missed. Needs the inspection's gradeable photo (R1). */
export const AddInspectorFindingInput = z.strictObject({
  inspectionId: Uuid,
  finding: InspectorFindingFields,
});
export const AddInspectorFindingOutput = z.strictObject({ finding: Finding, escalations: z.array(Escalation) });

// reviseFinding (after a void) --------------------------------------------------------------
/** Corrects an accepted finding once its report has been voided (C21a, D7). */
export const ReviseFindingInput = z.strictObject({
  findingId: Uuid,
  reason: NonBlank(1000),
  revision: InspectorFindingFields,
});
export const ReviseFindingOutput = z.strictObject({ finding: Finding, revision: Finding, escalations: z.array(Escalation) });

// raiseEscalation ------------------------------------------------------------------------
export const RaiseEscalationInput = z.strictObject({
  findingId: Uuid,
  reason: EscalationReason,
  detail: NonBlank(1000),
});
export const RaiseEscalationOutput = Escalation;

// acknowledgeEscalation -------------------------------------------------------------------
/** "A qualified person has seen this", not "resolved" (A34). Once only (C16). */
export const AcknowledgeEscalationInput = z.strictObject({ escalationId: Uuid, note: NonBlank(1000) });
export const AcknowledgeEscalationOutput = Escalation;
