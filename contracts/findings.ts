// Findings and the grading pipeline (domain model E14 to E20; R1 to R8, D1 to D4).
//
// Pipeline for one inspection (server only):
//   1. measure  : POST the gradeable photo to the measurement model     -> MeasureResponse
//   2. grade    : grading engine (Stage 5, plain code) maps the measurement to Ri and S1-S4
//   3. explain  : Claude ranks mechanisms and picks library recommendations -> ExplainOutput
//   4. store    : one draft AI finding with its hypotheses, recommendations and escalations
// The explain step cannot change a grade: its output schema has no grade fields (P-AI, C19a).

import { z } from "zod";
import {
  Confidence,
  DefectType,
  EscalationReason,
  EscalationSource,
  FindingOrigin,
  FindingStatus,
  NonBlank,
  Severity,
  Timestamp,
  Uuid,
  expectedAiSeverity,
  severityRank,
} from "./common";

export const MAX_MECHANISMS = 3; // R7

// Read models ---------------------------------------------------------------------------

/** GeoJSON MultiPolygon in image-pixel coordinates (A12). */
const Position = z.tuple([z.number().min(0), z.number().min(0)]);
const LinearRing = z.array(Position).min(4);
export const MultiPolygon = z.strictObject({
  type: z.literal("MultiPolygon"),
  coordinates: z.array(z.array(LinearRing)),
});


export const Escalation = z.strictObject({
  id: Uuid,
  findingId: Uuid,
  reason: EscalationReason,
  source: EscalationSource,
  detail: z.string().nullable(),
  acknowledgedBy: Uuid.nullable(),
  acknowledgedByName: z.string().nullable(),
  acknowledgedAt: Timestamp.nullable(),
  acknowledgementNote: z.string().nullable(),
});

export const Hypothesis = z.strictObject({
  rank: z.number().int().min(1).max(MAX_MECHANISMS),
  mechanismCode: z.string(),
  mechanismName: z.string(),
  visualEvidence: z.string(),
  /** Context answers cited as evidence (R7). */
  evidenceAnswerIds: z.array(Uuid),
});

export const FindingRecommendation = z.strictObject({
  code: z.string(),
  version: z.number().int().min(1),
  text: z.string(),
  sortOrder: z.number().int().min(1),
});

export const Measurement = z.strictObject({
  id: Uuid,
  modelName: z.string(),
  modelVersion: z.string(),
  percentAreaRusted: z.number().min(0).max(100),
  outline: MultiPolygon,
  modelConfidence: z.number().min(0).max(1),
});

export const Finding = z.strictObject({
  id: Uuid,
  inspectionId: Uuid,
  photoId: Uuid,
  origin: FindingOrigin,
  status: FindingStatus,
  supersedesFindingId: Uuid.nullable(),
  revisionReason: z.string().nullable(),
  defectType: DefectType,
  /** Cited on every grade (P-CITE). */
  standard: z.strictObject({ code: z.string(), edition: z.string() }),
  gradeValue: z.number().int(),
  rulesSeverity: Severity,
  severity: Severity,
  confidence: Confidence,
  severityRaisedReason: z.string().nullable(),
  possibleStaining: z.boolean(),
  summary: z.string().nullable(),
  measurement: Measurement.nullable(),
  hypotheses: z.array(Hypothesis).max(MAX_MECHANISMS),
  recommendations: z.array(FindingRecommendation),
  /** R6: depth and wall loss are never inferred from a photo. Always this value in Phase 1. */
  remainingLife: z.literal("needs_thickness_data"),
  createdBy: Uuid.nullable(),
  createdAt: Timestamp,
});

// Grading pipeline: gradeInspection --------------------------------------------------------

export const GradeInspectionInput = z.strictObject({ inspectionId: Uuid });
export const GradeInspectionOutput = z.strictObject({
  /** The new draft AI finding, with escalations the database added (R5, D2). */
  finding: Finding,
  escalations: z.array(Escalation),
});

// Outbound contract 1: measurement model (POST {MEASUREMENT_API_URL}/measure) ----------------

export const MeasureRequest = z.strictObject({
  /** Short-lived signed URL of the gradeable photo; the model service downloads it. */
  imageUrl: z.url(),
  widthPx: z.number().int().positive(),
  heightPx: z.number().int().positive(),
  /** From the gradeable-photo check; the model reports areas, not sizes, in Phase 1. */
  mmPerPx: z.number().positive(),
});

export const MeasureResponse = z.strictObject({
  modelName: NonBlank(100),
  modelVersion: NonBlank(100),
  percentAreaRusted: z.number().min(0).max(100),
  outline: MultiPolygon,
  modelConfidence: z.number().min(0).max(1),
});

// Grading engine output (Stage 5) ----------------------------------------------------------

/** What the grading engine hands to storage. Enforces D1 and D4 the same way the database does. */
export const AiGrade = z
  .strictObject({
    standardCode: z.literal("ISO 4628-3"),
    gradeValue: z.number().int().min(0).max(5),
    rulesSeverity: Severity,
    severity: Severity,
    confidence: Confidence,
    severityRaisedReason: NonBlank(500).nullable(),
    defectType: DefectType,
    gradingRulesVersion: NonBlank(50),
  })
  .superRefine((g, ctx) => {
    if (g.severity !== expectedAiSeverity(g.rulesSeverity, g.confidence)) {
      ctx.addIssue({
        code: "custom",
        path: ["severity"],
        message: "Low confidence raises the rules severity one step, capped at S4; otherwise it is unchanged (D1, D4)",
      });
    }
    const raised = severityRank(g.severity) > severityRank(g.rulesSeverity);
    if (raised !== (g.severityRaisedReason !== null)) {
      ctx.addIssue({ code: "custom", path: ["severityRaisedReason"], message: "A raised severity says why, and only then (R4)" });
    }
  });

// Outbound contract 2: Claude explain step ------------------------------------------------

/** What Anode sends to the explain step. The grade is context only; it cannot come back changed. */
export const ExplainInput = z.strictObject({
  grade: z.strictObject({ gradeValue: z.number().int(), severity: Severity, confidence: Confidence }),
  measurement: z.strictObject({ percentAreaRusted: z.number(), modelConfidence: z.number() }),
  asset: z.strictObject({
    assetType: z.string(),
    material: z.string(),
    coatingStatus: z.string(),
    environment: z.string(),
    isInsulated: z.boolean(),
  }),
  answers: z.array(z.strictObject({ answerId: Uuid, questionKey: z.string(), prompt: z.string(), value: z.unknown() })),
  allowedMechanisms: z.array(z.strictObject({ code: z.string(), name: z.string(), possibilityOnly: z.boolean() })),
  allowedRecommendations: z.array(z.strictObject({ code: z.string(), text: z.string() })),
});

/**
 * What the explain step must return (as a tool call / structured output). Strict: any extra
 * key, including any attempt at a grade, severity or confidence, fails validation, and the
 * server then stores the finding without an explanation rather than trusting the output.
 */
export const ExplainOutput = z
  .strictObject({
    hypotheses: z
      .array(
        z.strictObject({
          mechanismCode: z.string().min(1),
          visualEvidence: NonBlank(1000),
          evidenceAnswerIds: z.array(Uuid).max(10),
        }),
      )
      .max(MAX_MECHANISMS),
    recommendationCodes: z.array(z.string().min(1)).max(5),
    /** Escalations the explain step may add; it can never remove one (A30). */
    additionalEscalations: z.array(z.literal("suspected_cracking")).max(1),
    possibleStaining: z.boolean(),
    summary: NonBlank(1500),
  })
  .refine((o) => new Set(o.hypotheses.map((h) => h.mechanismCode)).size === o.hypotheses.length, {
    message: "Each mechanism appears once",
    path: ["hypotheses"],
  });

/** Second-stage check against the allowed lists the server sent (R7, R8, C17). */
export function checkExplainOutput(
  output: z.infer<typeof ExplainOutput>,
  input: z.infer<typeof ExplainInput>,
): string[] {
  const problems: string[] = [];
  const mechanisms = new Map(input.allowedMechanisms.map((m) => [m.code, m]));
  const recs = new Set(input.allowedRecommendations.map((r) => r.code));
  const answers = new Set(input.answers.map((a) => a.answerId));
  output.hypotheses.forEach((h, i) => {
    const m = mechanisms.get(h.mechanismCode);
    if (!m) problems.push(`hypothesis ${i + 1}: unknown mechanism ${h.mechanismCode}`);
    else if (i === 0 && m.possibilityOnly) problems.push(`${m.name} cannot be ranked first`);
    for (const a of h.evidenceAnswerIds) if (!answers.has(a)) problems.push(`hypothesis ${i + 1}: unknown answer ${a}`);
  });
  for (const r of output.recommendationCodes) if (!recs.has(r)) problems.push(`recommendation ${r} is not in the library`);
  return problems;
}
