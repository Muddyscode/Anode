// Reports: draft, sign, void, reissue (domain model E21, E22; R9, D7, C25 to C34).

import { z } from "zod";
import { NonBlank, OrgScoped, PageInput, ReportStatus, Sha256Hex, Timestamp, Uuid, page } from "./common";

export const ReportSummary = z.strictObject({
  id: Uuid,
  orgId: Uuid,
  title: z.string(),
  status: ReportStatus,
  inspectionIds: z.array(Uuid),
  createdAt: Timestamp,
  signedBy: Uuid.nullable(),
  signerName: z.string().nullable(),
  signerQualification: z.string().nullable(),
  signedAt: Timestamp.nullable(),
  pdfSha256: Sha256Hex.nullable(),
  disclaimerVersion: z.string().nullable(),
  replacesReportId: Uuid.nullable(),
  /** Set when a later report replaces this voided one. */
  replacedByReportId: Uuid.nullable(),
  voidedBy: Uuid.nullable(),
  voidedAt: Timestamp.nullable(),
  voidReason: z.string().nullable(),
});

/** What signing still needs, so the UI can show a checklist before the person signs. */
export const SignReadiness = z.strictObject({
  ready: z.boolean(),
  undecidedFindings: z.number().int().min(0),
  unacknowledgedEscalations: z.number().int().min(0),
  inspectionsInOtherReports: z.array(Uuid),
});

// listReports ---------------------------------------------------------------------------
/** Viewers see signed and void reports only (section 9). */
export const ListReportsInput = OrgScoped.extend({
  status: ReportStatus.optional(),
  page: PageInput.default({ limit: 25 }),
});
export const ListReportsOutput = page(ReportSummary);

// getReport -----------------------------------------------------------------------------
export const GetReportInput = z.strictObject({ reportId: Uuid });
export const GetReportOutput = z.strictObject({ report: ReportSummary, readiness: SignReadiness.nullable() });

// createReport --------------------------------------------------------------------------
export const CreateReportInput = OrgScoped.extend({
  id: Uuid.optional(),
  title: NonBlank(120),
  inspectionIds: z.array(Uuid).min(1).max(50).refine((ids) => new Set(ids).size === ids.length, "Each inspection once"),
  /** To reissue a voided report (C34). */
  replacesReportId: Uuid.nullable().default(null),
});
export const CreateReportOutput = GetReportOutput;

// updateDraftReport ---------------------------------------------------------------------
export const UpdateDraftReportInput = z
  .strictObject({
    reportId: Uuid,
    title: NonBlank(120).optional(),
    addInspectionIds: z.array(Uuid).max(50).default([]),
    removeInspectionIds: z.array(Uuid).max(50).default([]),
  })
  .refine((v) => v.title !== undefined || v.addInspectionIds.length > 0 || v.removeInspectionIds.length > 0, "Nothing to update")
  .refine((v) => !v.addInspectionIds.some((id) => v.removeInspectionIds.includes(id)), "An inspection cannot be added and removed at once");
export const UpdateDraftReportOutput = GetReportOutput;

// deleteDraftReport ---------------------------------------------------------------------
export const DeleteDraftReportInput = z.strictObject({ reportId: Uuid });
export const DeleteDraftReportOutput = z.strictObject({ deleted: z.literal(true) });

// signReport ------------------------------------------------------------------------------
/**
 * The signed-in inspector signs. The server checks readiness, renders the PDF (with the
 * "screening only" disclaimer, C31), stores it, then calls sign_report with its SHA-256.
 * The signature statement is shown to the person and must be confirmed explicitly.
 */
export const SignReportInput = z.strictObject({
  reportId: Uuid,
  confirmStatement: z.literal(true),
});
export const SignReportOutput = z.strictObject({ report: ReportSummary, downloadUrl: z.url() });

// voidReport ------------------------------------------------------------------------------
/** A signed report is never edited or deleted; it is voided with a reason (D7, C33). */
export const VoidReportInput = z.strictObject({ reportId: Uuid, reason: NonBlank(1000) });
export const VoidReportOutput = z.strictObject({
  report: ReportSummary,
  /** Inspections released for correction and a replacement report (A38). */
  releasedInspectionIds: z.array(Uuid),
});

// getReportDownloadUrl ------------------------------------------------------------------
export const GetReportDownloadUrlInput = z.strictObject({ reportId: Uuid });
export const GetReportDownloadUrlOutput = z.strictObject({ url: z.url(), expiresAt: Timestamp, pdfSha256: Sha256Hex });
