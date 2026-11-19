// The registry of every server action in Phase 1. One entry per action: who may call it,
// its input and output schemas, the error codes it can return, and the rules it enforces.
// docs/api.md documents each entry; contracts/actions.test.ts keeps the two in step.

import type { z } from "zod";
import type { ErrorCode } from "./errors";
import * as audit from "./audit";
import * as assets from "./assets";
import * as findings from "./findings";
import * as inspections from "./inspections";
import * as reference from "./reference";
import * as reports from "./reports";
import * as review from "./review";
import * as session from "./session";

/**
 * Who may call an action, checked by the server before it touches the database and again
 * by row-level security inside it:
 *   signed-in : any signed-in person
 *   member    : any member of the organisation (admin, inspector or viewer)
 *   writer    : an inspector or admin of the organisation
 *   admin     : an admin of the organisation
 */
export type Access = "signed-in" | "member" | "writer" | "admin";

export interface ActionContract {
  group: string;
  access: Access;
  input: z.ZodType;
  output: z.ZodType;
  /** Beyond the generic UNAUTHENTICATED, FORBIDDEN, VALIDATION, RATE_LIMITED and INTERNAL. */
  errors: readonly ErrorCode[];
  /** Business rules (R), decisions (D) and constraints (C) the action relies on. */
  rules: readonly string[];
}

const contract = <T extends ActionContract>(c: T) => c;

export const ACTIONS = {
  // Session and organisation
  getSession: contract({ group: "Session and organisation", access: "signed-in", input: session.GetSessionInput, output: session.GetSessionOutput, errors: [], rules: ["A2"] }),
  updateProfile: contract({ group: "Session and organisation", access: "signed-in", input: session.UpdateProfileInput, output: session.UpdateProfileOutput, errors: [], rules: ["A21"] }),
  renameOrganisation: contract({ group: "Session and organisation", access: "admin", input: session.RenameOrganisationInput, output: session.RenameOrganisationOutput, errors: ["NOT_FOUND"], rules: ["§9"] }),
  listMembers: contract({ group: "Session and organisation", access: "member", input: session.ListMembersInput, output: session.ListMembersOutput, errors: [], rules: ["§9"] }),
  changeMemberRole: contract({ group: "Session and organisation", access: "admin", input: session.ChangeMemberRoleInput, output: session.ChangeMemberRoleOutput, errors: ["NOT_FOUND", "LAST_ADMIN"], rules: ["§9"] }),

  // Reference data
  getReferenceData: contract({ group: "Reference data", access: "signed-in", input: reference.GetReferenceDataInput, output: reference.GetReferenceDataOutput, errors: [], rules: ["R3", "R7", "R8", "C2"] }),

  // Asset register
  listAssets: contract({ group: "Asset register", access: "member", input: assets.ListAssetsInput, output: assets.ListAssetsOutput, errors: [], rules: [] }),
  getAsset: contract({ group: "Asset register", access: "member", input: assets.GetAssetInput, output: assets.GetAssetOutput, errors: ["NOT_FOUND"], rules: [] }),
  createAsset: contract({ group: "Asset register", access: "writer", input: assets.CreateAssetInput, output: assets.CreateAssetOutput, errors: ["CONFLICT"], rules: ["A10", "C6"] }),
  updateAsset: contract({ group: "Asset register", access: "writer", input: assets.UpdateAssetInput, output: assets.UpdateAssetOutput, errors: ["NOT_FOUND"], rules: ["C6"] }),
  archiveAsset: contract({ group: "Asset register", access: "writer", input: assets.ArchiveAssetInput, output: assets.ArchiveAssetOutput, errors: ["NOT_FOUND"], rules: ["§2"] }),
  createPoint: contract({ group: "Asset register", access: "writer", input: assets.CreatePointInput, output: assets.CreatePointOutput, errors: ["NOT_FOUND", "DUPLICATE_POINT_LABEL", "CONFLICT"], rules: ["C5"] }),
  updatePoint: contract({ group: "Asset register", access: "writer", input: assets.UpdatePointInput, output: assets.UpdatePointOutput, errors: ["NOT_FOUND", "DUPLICATE_POINT_LABEL"], rules: ["C5"] }),
  archivePoint: contract({ group: "Asset register", access: "writer", input: assets.ArchivePointInput, output: assets.ArchivePointOutput, errors: ["NOT_FOUND"], rules: ["§2"] }),

  // Inspections and photos
  listInspections: contract({ group: "Inspections and photos", access: "member", input: inspections.ListInspectionsInput, output: inspections.ListInspectionsOutput, errors: [], rules: [] }),
  getInspection: contract({ group: "Inspections and photos", access: "member", input: inspections.GetInspectionInput, output: inspections.GetInspectionOutput, errors: ["NOT_FOUND"], rules: ["R6", "C21a"] }),
  createInspection: contract({ group: "Inspections and photos", access: "writer", input: inspections.CreateInspectionInput, output: inspections.CreateInspectionOutput, errors: ["NOT_FOUND", "INSPECTED_IN_FUTURE", "CONFLICT"], rules: ["C3", "C7"] }),
  updateInspection: contract({ group: "Inspections and photos", access: "writer", input: inspections.UpdateInspectionInput, output: inspections.UpdateInspectionOutput, errors: ["NOT_FOUND", "INSPECTED_IN_FUTURE", "INSPECTION_LOCKED"], rules: ["C7", "C30"] }),
  saveContextAnswers: contract({ group: "Inspections and photos", access: "writer", input: inspections.SaveContextAnswersInput, output: inspections.SaveContextAnswersOutput, errors: ["NOT_FOUND", "ANSWER_INVALID", "INSPECTION_LOCKED"], rules: ["C8", "C30"] }),
  requestPhotoUpload: contract({ group: "Inspections and photos", access: "writer", input: inspections.RequestPhotoUploadInput, output: inspections.RequestPhotoUploadOutput, errors: ["NOT_FOUND", "PHOTO_TOO_LARGE", "PHOTO_ALREADY_GRADED", "INSPECTION_LOCKED"], rules: ["C10a", "C30", "§9"] }),
  confirmPhoto: contract({ group: "Inspections and photos", access: "writer", input: inspections.ConfirmPhotoInput, output: inspections.ConfirmPhotoOutput, errors: ["NOT_FOUND", "PHOTO_UPLOAD_MISSING", "PHOTO_ALREADY_CHECKED", "PHOTO_ALREADY_GRADED", "INSPECTION_LOCKED"], rules: ["R1", "D6", "A6", "A7", "A8", "C9", "C10", "C10a", "C10b"] }),

  // Grading pipeline
  gradeInspection: contract({ group: "Grading", access: "writer", input: findings.GradeInspectionInput, output: findings.GradeInspectionOutput, errors: ["NOT_FOUND", "PHOTO_NOT_GRADEABLE", "SCOPE_NOT_SUPPORTED", "MEASUREMENT_UNAVAILABLE", "INSPECTION_LOCKED"], rules: ["R1", "R2", "R4", "R5", "R6", "R7", "R8", "D1", "D2", "D4", "C12", "C13", "C15", "C16b", "C19a", "C32"] }),

  // Review and escalation
  reviewFinding: contract({ group: "Review and escalation", access: "writer", input: review.ReviewFindingInput, output: review.ReviewFindingOutput, errors: ["NOT_FOUND", "REVIEW_NOT_ALLOWED", "REASON_REQUIRED", "GRADE_OUT_OF_RANGE", "MECHANISM_NOT_ALLOWED", "RECOMMENDATION_NOT_ALLOWED", "INSPECTION_LOCKED"], rules: ["R9", "D3", "A17", "A18", "C20", "C21", "C22", "C23"] }),
  addInspectorFinding: contract({ group: "Review and escalation", access: "writer", input: review.AddInspectorFindingInput, output: review.AddInspectorFindingOutput, errors: ["NOT_FOUND", "PHOTO_NOT_GRADEABLE", "GRADE_OUT_OF_RANGE", "MECHANISM_NOT_ALLOWED", "RECOMMENDATION_NOT_ALLOWED", "INSPECTION_LOCKED"], rules: ["R1", "R5", "D2", "D3", "A13", "C20"] }),
  reviseFinding: contract({ group: "Review and escalation", access: "writer", input: review.ReviseFindingInput, output: review.ReviseFindingOutput, errors: ["NOT_FOUND", "REVISION_NOT_ALLOWED", "REASON_REQUIRED", "GRADE_OUT_OF_RANGE", "MECHANISM_NOT_ALLOWED", "RECOMMENDATION_NOT_ALLOWED", "INSPECTION_LOCKED"], rules: ["D7", "A38", "C21a"] }),
  raiseEscalation: contract({ group: "Review and escalation", access: "writer", input: review.RaiseEscalationInput, output: review.RaiseEscalationOutput, errors: ["NOT_FOUND", "CONFLICT", "INSPECTION_LOCKED"], rules: ["R5", "C16c"] }),
  acknowledgeEscalation: contract({ group: "Review and escalation", access: "writer", input: review.AcknowledgeEscalationInput, output: review.AcknowledgeEscalationOutput, errors: ["NOT_FOUND", "ESCALATION_IMMUTABLE", "INSPECTION_LOCKED"], rules: ["R5", "D8", "A34", "C16"] }),

  // Reports
  listReports: contract({ group: "Reports", access: "member", input: reports.ListReportsInput, output: reports.ListReportsOutput, errors: [], rules: ["§9"] }),
  getReport: contract({ group: "Reports", access: "member", input: reports.GetReportInput, output: reports.GetReportOutput, errors: ["NOT_FOUND"], rules: ["§9"] }),
  createReport: contract({ group: "Reports", access: "writer", input: reports.CreateReportInput, output: reports.CreateReportOutput, errors: ["NOT_FOUND", "INSPECTION_ALREADY_REPORTED", "REPLACEMENT_INVALID", "CONFLICT"], rules: ["A20", "C29", "C34"] }),
  updateDraftReport: contract({ group: "Reports", access: "writer", input: reports.UpdateDraftReportInput, output: reports.UpdateDraftReportOutput, errors: ["NOT_FOUND", "REPORT_NOT_DRAFT", "INSPECTION_ALREADY_REPORTED"], rules: ["C29", "C30"] }),
  deleteDraftReport: contract({ group: "Reports", access: "writer", input: reports.DeleteDraftReportInput, output: reports.DeleteDraftReportOutput, errors: ["NOT_FOUND", "REPORT_IMMUTABLE"], rules: ["C30"] }),
  signReport: contract({ group: "Reports", access: "writer", input: reports.SignReportInput, output: reports.SignReportOutput, errors: ["NOT_FOUND", "REPORT_NOT_DRAFT", "REPORT_EMPTY", "FINDINGS_UNDECIDED", "ESCALATIONS_UNACKNOWLEDGED", "INSPECTION_ALREADY_REPORTED", "REPORT_PDF_MISSING"], rules: ["R5", "R9", "D8", "C25", "C26", "C27", "C28", "C31"] }),
  voidReport: contract({ group: "Reports", access: "writer", input: reports.VoidReportInput, output: reports.VoidReportOutput, errors: ["NOT_FOUND", "REPORT_NOT_SIGNED", "REASON_REQUIRED"], rules: ["D7", "D8", "A38", "C33"] }),
  getReportDownloadUrl: contract({ group: "Reports", access: "member", input: reports.GetReportDownloadUrlInput, output: reports.GetReportDownloadUrlOutput, errors: ["NOT_FOUND"], rules: ["§9"] }),

  // Audit
  listAuditEvents: contract({ group: "Audit", access: "writer", input: audit.ListAuditEventsInput, output: audit.ListAuditEventsOutput, errors: [], rules: ["D8", "A41"] }),
} as const satisfies Record<string, ActionContract>;

export type ActionName = keyof typeof ACTIONS;

/** Outbound contracts: services Anode's server calls, not actions the app exposes. */
export const OUTBOUND = {
  measure: { request: findings.MeasureRequest, response: findings.MeasureResponse },
  explain: { request: findings.ExplainInput, response: findings.ExplainOutput },
} as const;
