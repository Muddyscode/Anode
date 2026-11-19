// Error contract: stable error codes, the error envelope, and the mapping from every
// database error Anode can raise to a code and a user-facing message.
// contracts/errors.test.ts fails if a migration raises an error this file does not map.

import { z } from "zod";

export const ErrorCode = z.enum([
  // Generic
  "UNAUTHENTICATED",
  "FORBIDDEN",
  "NOT_FOUND",
  "VALIDATION",
  "CONFLICT",
  "RATE_LIMITED",
  "INTERNAL",
  // Membership and roles (C3, section 9)
  "NOT_A_MEMBER",
  "ROLE_INSUFFICIENT",
  "LAST_ADMIN",
  // Asset register and inspections
  "DUPLICATE_POINT_LABEL",
  "INSPECTED_IN_FUTURE",
  "ANSWER_INVALID",
  "INSPECTION_LOCKED",
  // Photos (R1, D6)
  "PHOTO_NOT_GRADEABLE",
  "PHOTO_ALREADY_CHECKED",
  "PHOTO_NEEDS_SCALE",
  "PHOTO_ALREADY_GRADED",
  "PHOTO_TOO_LARGE",
  "PHOTO_UPLOAD_MISSING",
  // Findings, mechanisms, recommendations (R2 to R9)
  "GRADE_OUT_OF_RANGE",
  "SEVERITY_RULE",
  "FINDING_IMMUTABLE",
  "REVIEW_NOT_ALLOWED",
  "REVISION_NOT_ALLOWED",
  "REASON_REQUIRED",
  "MECHANISM_NOT_ALLOWED",
  "RECOMMENDATION_NOT_ALLOWED",
  "ESCALATION_IMMUTABLE",
  // Reports (R9, D7)
  "FINDINGS_UNDECIDED",
  "ESCALATIONS_UNACKNOWLEDGED",
  "REPORT_EMPTY",
  "REPORT_NOT_DRAFT",
  "REPORT_NOT_SIGNED",
  "REPORT_IMMUTABLE",
  "REPORT_PDF_MISSING",
  "INSPECTION_ALREADY_REPORTED",
  "REPLACEMENT_INVALID",
  // Grading pipeline (outbound services)
  "SCOPE_NOT_SUPPORTED",
  "MEASUREMENT_UNAVAILABLE",
  // Internal invariants: only reachable by a bug in Anode's own server code
  "INTERNAL_INVARIANT",
]);
export type ErrorCode = z.infer<typeof ErrorCode>;

/** The error half of every action result. `field` names the offending input path, if any. */
export const ApiError = z.strictObject({
  code: ErrorCode,
  message: z.string().min(1),
  field: z.string().min(1).optional(),
});
export type ApiError = z.infer<typeof ApiError>;

/** Every server action returns `{ ok: true, data }` or `{ ok: false, error }`. */
export const result = <T extends z.ZodType>(data: T) =>
  z.discriminatedUnion("ok", [
    z.strictObject({ ok: z.literal(true), data }),
    z.strictObject({ ok: z.literal(false), error: ApiError }),
  ]);

// Database error mapping -----------------------------------------------------------

export interface DbErrorRule {
  code: ErrorCode;
  /** Shown to the person. Plain words; no table or constraint names. */
  message: string;
  /** Matches a named constraint or unique index in the Postgres error text. */
  constraint?: string;
  /** Matches the message raised by Anode's own database functions. */
  pattern?: RegExp;
}

/** Ordered: the first rule that matches wins. Constraint rules come first. */
export const DB_ERROR_RULES: readonly DbErrorRule[] = [
  // Named constraints and unique indexes
  { constraint: "photo_storage_path", code: "VALIDATION", message: "The photo's storage path is not valid." },
  { constraint: "photo_pending_unchecked", code: "INTERNAL_INVARIANT", message: "Something went wrong recording the photo check." },
  { constraint: "photo_gradeable_needs_scale", code: "PHOTO_NEEDS_SCALE", message: "A photo can only be graded with a scale reference in view: the Anode scale card, a ruler or a tape measure." },
  { constraint: "photo_rejected_needs_reason", code: "INTERNAL_INVARIANT", message: "Something went wrong recording the photo check." },
  { constraint: "photo_unscaled_is_rejected", code: "PHOTO_NEEDS_SCALE", message: "No scale reference was found in the photo. Retake it with the Anode scale card, a ruler or a tape measure in view." },
  { constraint: "photo_colour_needs_scale_card", code: "INTERNAL_INVARIANT", message: "Colour correction needs the Anode scale card." },
  { constraint: "photo_one_gradeable", code: "PHOTO_ALREADY_GRADED", message: "This inspection already has a gradeable photo. Start a new inspection to photograph the point again." },
  { constraint: "finding_ai_provenance", code: "INTERNAL_INVARIANT", message: "An AI finding must come from a measurement." },
  { constraint: "finding_inspector_author", code: "INTERNAL_INVARIANT", message: "An inspector's finding must record who wrote it." },
  { constraint: "finding_inspector_severity_is_own", code: "VALIDATION", message: "Your finding's severity is your own judgement; set the rules severity to the same value." },
  { constraint: "finding_low_confidence_raises_severity", code: "SEVERITY_RULE", message: "When the AI's confidence is low, its severity must be raised one step (rule 4)." },
  { constraint: "finding_raise_has_reason", code: "SEVERITY_RULE", message: "A raised severity must say why." },
  { constraint: "finding_superseded_once", code: "REVISION_NOT_ALLOWED", message: "This finding has already been revised." },
  { constraint: "inspection_point_label_unique", code: "DUPLICATE_POINT_LABEL", message: "This asset already has a point with that label." },
  { constraint: "recommendation_one_active_version", code: "INTERNAL_INVARIANT", message: "A recommendation can have only one active version." },
  { constraint: "report_replaced_once", code: "REPLACEMENT_INVALID", message: "This voided report already has a replacement." },

  // Messages raised by Anode's database functions
  { pattern: /must be a member of the organisation$/, code: "NOT_A_MEMBER", message: "That person is not a member of this organisation." },
  { pattern: /must be an inspector or admin of the organisation$/, code: "ROLE_INSUFFICIENT", message: "Only an inspector or admin can do this." },
  { pattern: /^an organisation must keep at least one admin$/, code: "LAST_ADMIN", message: "An organisation must keep at least one admin." },
  { pattern: /^membership organisation and user cannot change$/, code: "INTERNAL_INVARIANT", message: "Remove the membership and add it again instead." },

  { pattern: /^inspected_at cannot be in the future$/, code: "INSPECTED_IN_FUTURE", message: "The inspection date cannot be in the future." },
  { pattern: /^a new inspection starts as draft$/, code: "INTERNAL_INVARIANT", message: "A new inspection starts as a draft." },
  { pattern: /^inspection status is set by Anode, not directly$/, code: "INTERNAL_INVARIANT", message: "An inspection's status updates itself." },
  { pattern: /^an inspection cannot move to another point or organisation$/, code: "VALIDATION", message: "An inspection cannot move to another point." },
  { pattern: /^a reported inspection cannot be deleted$/, code: "INSPECTION_LOCKED", message: "This inspection is in a signed report and cannot be deleted." },
  { pattern: /^this inspection is in a signed report and is locked$/, code: "INSPECTION_LOCKED", message: "This inspection is in a signed report and is locked. Void the report to correct it." },
  { pattern: /^question .+ is not active$/, code: "ANSWER_INVALID", message: "That question is no longer asked." },
  { pattern: /^answer does not match the .+ question .+$/, code: "ANSWER_INVALID", message: "That answer does not fit the question." },
  { pattern: /^an answer cannot move to another inspection or question$/, code: "INTERNAL_INVARIANT", message: "An answer belongs to one question." },

  { pattern: /^only a gradeable photo can be measured or graded \(rule 1\)$/, code: "PHOTO_NOT_GRADEABLE", message: "This photo did not pass the photo check, so it cannot be graded. Retake it." },
  { pattern: /^a photo's gradeability is decided once; upload a new photo to retake$/, code: "PHOTO_ALREADY_CHECKED", message: "This photo has already been checked. Upload a new photo to retake." },
  { pattern: /^only the gradeability check result can be written to a photo$/, code: "INTERNAL_INVARIANT", message: "A photo cannot be edited." },
  { pattern: /^photos are kept, not deleted$/, code: "FORBIDDEN", message: "Photos are kept for the record and cannot be deleted." },

  { pattern: /^grade .+ is outside .+ \(.+ to .+\)$/, code: "GRADE_OUT_OF_RANGE", message: "That grade is outside the standard's scale." },
  { pattern: /^standard .+ is not active$/, code: "VALIDATION", message: "That standard is not in use." },
  { pattern: /^a finding cannot be edited; an inspector edit creates a new finding \(rule 9\)$/, code: "FINDING_IMMUTABLE", message: "Findings are never edited. Review it as an edit to record your own finding." },
  { pattern: /^a finding cannot move from .+ to .+$/, code: "INTERNAL_INVARIANT", message: "That change of status is not possible." },
  { pattern: /^finding status changes only through a review$/, code: "INTERNAL_INVARIANT", message: "A finding's status changes only through a review." },
  { pattern: /^findings are kept, not deleted$/, code: "FORBIDDEN", message: "Findings are kept for the record and cannot be deleted." },
  { pattern: /^this finding is closed to changes$/, code: "FINDING_IMMUTABLE", message: "This finding has been decided and cannot change." },
  { pattern: /^only a draft AI finding can be reviewed$/, code: "REVIEW_NOT_ALLOWED", message: "This finding has already been reviewed." },
  { pattern: /^only a draft AI finding, or an accepted finding after its report was voided, can be superseded$/, code: "REVISION_NOT_ALLOWED", message: "This finding cannot be revised now. Void its report first." },
  { pattern: /^revising a finding after a void needs a reason$/, code: "REASON_REQUIRED", message: "Say why you are revising this finding." },
  { pattern: /^an edit must point at the inspector finding that supersedes this one$/, code: "INTERNAL_INVARIANT", message: "The edit and its revised finding do not match." },
  { pattern: /^this finding already has an inspector revision; review it as an edit$/, code: "REVIEW_NOT_ALLOWED", message: "You have already revised this finding; it is reviewed as an edit." },
  { pattern: /^.+ can be listed only as a possibility, not ranked first$/, code: "MECHANISM_NOT_ALLOWED", message: "This mechanism can be listed only as a possibility, not ranked first." },
  { pattern: /^mechanism .+ is not active$/, code: "MECHANISM_NOT_ALLOWED", message: "That mechanism is not in use." },
  { pattern: /^evidence must be an answer from the same inspection$/, code: "VALIDATION", message: "Evidence must come from this inspection's answers." },
  { pattern: /^recommendation .+ version .+ is not the current library entry$/, code: "RECOMMENDATION_NOT_ALLOWED", message: "That recommendation has been updated. Reload and choose again." },
  { pattern: /^recommendation .+ applies from .+ upwards$/, code: "RECOMMENDATION_NOT_ALLOWED", message: "That recommendation is not offered at this severity." },

  { pattern: /^escalations cannot be removed \(rule 5\)$/, code: "ESCALATION_IMMUTABLE", message: "Escalations cannot be removed." },
  { pattern: /^an escalation is acknowledged after it is raised$/, code: "INTERNAL_INVARIANT", message: "An escalation is acknowledged after it is raised." },
  { pattern: /^this escalation is already acknowledged$/, code: "ESCALATION_IMMUTABLE", message: "This escalation has already been acknowledged." },
  { pattern: /^an escalation can only be acknowledged$/, code: "ESCALATION_IMMUTABLE", message: "An escalation can only be acknowledged." },
  { pattern: /^only the acknowledgement of an escalation can be written$/, code: "ESCALATION_IMMUTABLE", message: "An escalation can only be acknowledged." },

  { pattern: /^report not found$/, code: "NOT_FOUND", message: "Report not found." },
  { pattern: /^a new report starts as draft$/, code: "INTERNAL_INVARIANT", message: "A new report starts as a draft." },
  { pattern: /^reports are signed only through sign_report$/, code: "INTERNAL_INVARIANT", message: "Reports are signed through the sign-off step." },
  { pattern: /^a .+ report cannot be changed$/, code: "REPORT_IMMUTABLE", message: "A signed or voided report cannot be changed. Void it and issue a replacement." },
  { pattern: /^a signed or voided report is never deleted$/, code: "REPORT_IMMUTABLE", message: "Signed and voided reports are kept for the record." },
  { pattern: /^a report cannot move to another organisation$/, code: "INTERNAL_INVARIANT", message: "A report belongs to one organisation." },
  { pattern: /^a .+ report's contents cannot change$/, code: "REPORT_NOT_DRAFT", message: "Only a draft report's contents can change." },
  { pattern: /^report contents are added or removed, not changed$/, code: "INTERNAL_INVARIANT", message: "Add or remove inspections instead." },
  { pattern: /^a report can only replace a voided report$/, code: "REPLACEMENT_INVALID", message: "A report can only replace a voided report." },
  { pattern: /^this inspection is already in a signed report$/, code: "INSPECTION_ALREADY_REPORTED", message: "This inspection is already in a signed report." },
  { pattern: /^this inspection is already in another report$/, code: "INSPECTION_ALREADY_REPORTED", message: "This inspection is already in another report." },
  { pattern: /^an inspection in this report is already in another report$/, code: "INSPECTION_ALREADY_REPORTED", message: "An inspection in this report is already in another report." },
  { pattern: /^only a draft report can be signed$/, code: "REPORT_NOT_DRAFT", message: "Only a draft report can be signed." },
  { pattern: /^a report must cover at least one inspection$/, code: "REPORT_EMPTY", message: "Add at least one inspection before signing." },
  { pattern: /^every finding must be accepted, edited or rejected before signing \(rule 9\)$/, code: "FINDINGS_UNDECIDED", message: "Accept, edit or reject every finding before signing." },
  { pattern: /^every escalation must be acknowledged by an inspector before signing \(rule 5\)$/, code: "ESCALATIONS_UNACKNOWLEDGED", message: "Acknowledge every escalation before signing." },
  { pattern: /^the report PDF has not been stored at .+$/, code: "REPORT_PDF_MISSING", message: "The report PDF could not be stored. Try signing again." },
  { pattern: /^only a signed report can be voided$/, code: "REPORT_NOT_SIGNED", message: "Only a signed report can be voided." },
  { pattern: /^voiding a report needs a reason$/, code: "REASON_REQUIRED", message: "Say why you are voiding this report." },

  { pattern: /rows cannot be changed or deleted$/, code: "FORBIDDEN", message: "This record is permanent and cannot be changed." },
  { pattern: /cannot be truncated$/, code: "FORBIDDEN", message: "This record is permanent." },
];

/** The shape of a Postgres error as supabase-js and postgres clients report it. */
export interface DbErrorLike {
  /** SQLSTATE, for example "23514". */
  code?: string;
  message?: string;
}

/** Fallbacks by SQLSTATE when no specific rule matches. */
const SQLSTATE_FALLBACK: Record<string, { code: ErrorCode; message: string }> = {
  "42501": { code: "FORBIDDEN", message: "You do not have permission to do this." },
  "23503": { code: "NOT_FOUND", message: "Something this refers to does not exist or is not yours." },
  "23505": { code: "CONFLICT", message: "That already exists." },
  "23502": { code: "VALIDATION", message: "A required value is missing." },
  "23514": { code: "VALIDATION", message: "That value is not allowed." },
  "22P02": { code: "VALIDATION", message: "A value is in the wrong format." },
  P0002: { code: "NOT_FOUND", message: "Not found." },
};

const CONSTRAINT_IN_MESSAGE = /constraint "([a-z0-9_]+)"/;

/** Maps a database error to Anode's error envelope. Never leaks SQL text to the person. */
export function mapDbError(err: DbErrorLike): ApiError {
  const text = err.message ?? "";
  const constraint = CONSTRAINT_IN_MESSAGE.exec(text)?.[1];
  for (const rule of DB_ERROR_RULES) {
    if (rule.constraint !== undefined ? rule.constraint === constraint : rule.pattern?.test(text)) {
      return { code: rule.code, message: rule.message };
    }
  }
  if (text.includes("row-level security")) {
    return { code: "FORBIDDEN", message: "You do not have permission to do this." };
  }
  const fallback = err.code !== undefined ? SQLSTATE_FALLBACK[err.code] : undefined;
  return fallback ?? { code: "INTERNAL", message: "Something went wrong. Please try again." };
}
