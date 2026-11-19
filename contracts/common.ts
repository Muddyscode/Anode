// Shared schemas for Anode's API contracts.
// Enumerations mirror the Postgres enums in supabase/migrations/20261118000100_foundation.sql;
// contracts/enums.test.ts fails if the two drift apart.

import { z } from "zod";

// Identifiers and scalars -----------------------------------------------------

export const Uuid = z.uuid();
export type Uuid = z.infer<typeof Uuid>;

/** Text with visible content, trimmed (domain model C4). */
export const NonBlank = (max: number) => z.string().trim().min(1).max(max);

/** ISO 8601 timestamp with offset, as Postgres timestamptz serialises it. */
export const Timestamp = z.iso.datetime({ offset: true });

export const Sha256Hex = z.string().regex(/^[0-9a-f]{64}$/, "64 lowercase hex characters");

// Enumerations (domain model section 5) ----------------------------------------

export const MemberRole = z.enum(["admin", "inspector", "viewer"]);
export const GradeScale = z.enum(["iso_4628_3_ri"]);
export const Severity = z.enum(["S1", "S2", "S3", "S4"]);
export const Confidence = z.enum(["low", "medium", "high"]);
export const AnswerType = z.enum(["boolean", "single_choice", "number", "text"]);
export const AssetType = z.enum(["pipe", "tank", "beam", "hull_plate", "bolt", "structure", "other"]);
export const Material = z.enum([
  "carbon_steel",
  "low_alloy_steel",
  "stainless_steel",
  "galvanised_steel",
  "cast_iron",
  "other",
  "unknown",
]);
export const CoatingStatus = z.enum(["coated", "uncoated", "unknown"]);
export const Environment = z.enum([
  "atmospheric_rural",
  "atmospheric_urban",
  "atmospheric_industrial",
  "atmospheric_marine",
  "immersed",
  "buried",
  "indoor",
  "other",
]);
export const InspectionStatus = z.enum(["draft", "ready_for_signoff", "reported"]);
export const Gradeability = z.enum(["pending", "gradeable", "rejected"]);
export const PhotoRejectionReason = z.enum([
  "out_of_focus",
  "uneven_lighting",
  "glare",
  "no_scale_reference",
  "surface_not_visible",
]);
/** D6: Anode scale card preferred; ruler or tape measure accepted; coins are not accepted. */
export const ScaleReference = z.enum(["anode_scale_card", "ruler", "tape_measure", "none"]);
export const FindingOrigin = z.enum(["ai", "inspector"]);
export const DefectType = z.enum(["rusting", "pitting", "suspected_cracking", "coating_breakdown", "other"]);
export const FindingStatus = z.enum(["draft", "accepted", "rejected", "superseded"]);
export const EscalationReason = z.enum([
  "severity_s4",
  "pressure_pitting_or_wall_loss",
  "suspected_cracking",
  "suspected_cui",
  "injury_risk",
]);
export const EscalationSource = z.enum(["grading_rules", "explain_step", "inspector"]);
export const ReviewDecision = z.enum(["accept", "edit", "reject"]);
export const ReportStatus = z.enum(["draft", "signed", "void"]);
export const AuditActorKind = z.enum(["user", "server"]);
export const AuditAction = z.enum([
  "report_signed",
  "report_voided",
  "escalation_acknowledged",
  "finding_accepted",
  "finding_edited",
  "finding_rejected",
  "finding_revised",
]);

/** Every enum above, keyed by its Postgres type name, for the drift test. */
export const DB_ENUMS = {
  member_role: MemberRole,
  grade_scale: GradeScale,
  severity: Severity,
  confidence: Confidence,
  answer_type: AnswerType,
  asset_type: AssetType,
  material: Material,
  coating_status: CoatingStatus,
  environment: Environment,
  inspection_status: InspectionStatus,
  gradeability: Gradeability,
  photo_rejection_reason: PhotoRejectionReason,
  scale_reference: ScaleReference,
  finding_origin: FindingOrigin,
  defect_type: DefectType,
  finding_status: FindingStatus,
  escalation_reason: EscalationReason,
  escalation_source: EscalationSource,
  review_decision: ReviewDecision,
  report_status: ReportStatus,
  audit_actor_kind: AuditActorKind,
  audit_action: AuditAction,
} as const;

// Severity order (R3) and the D1 rule, shared by every contract that carries a severity.

const SEVERITY_ORDER = Severity.options;

export function severityRank(s: z.infer<typeof Severity>): number {
  return SEVERITY_ORDER.indexOf(s);
}

/** D1: low confidence raises the rules severity one step, capped at S4. */
export function expectedAiSeverity(
  rules: z.infer<typeof Severity>,
  confidence: z.infer<typeof Confidence>,
): z.infer<typeof Severity> {
  if (confidence !== "low") return rules;
  const next = SEVERITY_ORDER[Math.min(severityRank(rules) + 1, SEVERITY_ORDER.length - 1)];
  return next ?? "S4";
}

// Paging ---------------------------------------------------------------------------

export const PageInput = z.strictObject({
  limit: z.number().int().min(1).max(100).default(25),
  /** Opaque cursor from the previous page's `nextCursor`. */
  cursor: z.string().min(1).max(200).optional(),
});

export const page = <T extends z.ZodType>(item: T) =>
  z.strictObject({
    items: z.array(item),
    nextCursor: z.string().nullable(),
  });

// Organisation scope: every tenant action names the organisation it acts in.
export const OrgScoped = z.strictObject({ orgId: Uuid });
