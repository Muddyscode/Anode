// Inspections, context answers and photos (domain model E11 to E13; R1, D6, C7, C8, C10a).

import { z } from "zod";
import {
  Gradeability,
  InspectionStatus,
  NonBlank,
  OrgScoped,
  PageInput,
  PhotoRejectionReason,
  ScaleReference,
  Severity,
  Sha256Hex,
  Timestamp,
  Uuid,
  page,
} from "./common";
import { Escalation, Finding } from "./findings";

export const InspectionSummary = z.strictObject({
  id: Uuid,
  orgId: Uuid,
  pointId: Uuid,
  assetId: Uuid,
  assetName: z.string(),
  pointLabel: z.string(),
  inspectorId: Uuid,
  inspectorName: z.string(),
  inspectedAt: Timestamp,
  /** Derived by the database from the findings (domain model §14). */
  status: InspectionStatus,
  notes: z.string().nullable(),
  /** Highest severity among accepted or draft findings, for lists. */
  worstSeverity: Severity.nullable(),
  openEscalations: z.number().int().min(0),
});

export const ContextAnswerValue = z.union([z.boolean(), z.number().finite(), z.string().trim().min(1).max(500)]);

export const ContextAnswer = z.strictObject({
  id: Uuid,
  questionKey: z.string(),
  value: ContextAnswerValue,
});

export const Photo = z.strictObject({
  id: Uuid,
  mimeType: z.string(),
  widthPx: z.number().int().positive(),
  heightPx: z.number().int().positive(),
  capturedAt: Timestamp.nullable(),
  gradeability: Gradeability,
  rejectionReasons: z.array(PhotoRejectionReason),
  scaleReference: ScaleReference,
  colourCorrected: z.boolean(),
  /** Short-lived signed URL to display the image. */
  viewUrl: z.url(),
  createdAt: Timestamp,
});

// listInspections ----------------------------------------------------------------------
export const ListInspectionsInput = OrgScoped.extend({
  status: InspectionStatus.optional(),
  pointId: Uuid.optional(),
  assetId: Uuid.optional(),
  page: PageInput.default({ limit: 25 }),
});
export const ListInspectionsOutput = page(InspectionSummary);

// getInspection ------------------------------------------------------------------------
export const GetInspectionInput = z.strictObject({ inspectionId: Uuid });
export const GetInspectionOutput = z.strictObject({
  inspection: InspectionSummary,
  answers: z.array(ContextAnswer),
  /** Every photo, rejected retakes included (A6), newest first. */
  photos: z.array(Photo),
  findings: z.array(Finding),
  escalations: z.array(Escalation),
  /** True when the inspection was in a voided report, so accepted findings may be revised (C21a). */
  revisable: z.boolean(),
});

// createInspection ---------------------------------------------------------------------
export const CreateInspectionInput = z.strictObject({
  id: Uuid.optional(),
  pointId: Uuid,
  /** Defaults to now. Not in the future (C7). */
  inspectedAt: Timestamp.optional(),
  notes: NonBlank(2000).nullable().default(null),
});
export const CreateInspectionOutput = InspectionSummary;

// updateInspection ---------------------------------------------------------------------
export const UpdateInspectionInput = z
  .strictObject({
    inspectionId: Uuid,
    patch: z.strictObject({ inspectedAt: Timestamp, notes: NonBlank(2000).nullable() }).partial(),
  })
  .refine(({ patch }) => Object.keys(patch).length > 0, "Nothing to update");
export const UpdateInspectionOutput = InspectionSummary;

// saveContextAnswers -------------------------------------------------------------------
/** Upserts answers by question key. Each value must fit its question's type (C8); the
 *  server checks that against the reference data before writing. */
export const SaveContextAnswersInput = z.strictObject({
  inspectionId: Uuid,
  answers: z
    .array(z.strictObject({ questionKey: z.string().min(1).max(64), value: ContextAnswerValue }))
    .min(1)
    .max(50)
    .refine((a) => new Set(a.map((x) => x.questionKey)).size === a.length, "Each question is answered once"),
});
export const SaveContextAnswersOutput = z.strictObject({ answers: z.array(ContextAnswer) });

// requestPhotoUpload -------------------------------------------------------------------
export const PHOTO_MIME_TYPES = ["image/jpeg", "image/png", "image/heic", "image/webp"] as const;
export const PHOTO_MAX_BYTES = 20 * 1024 * 1024; // matches the storage bucket limit

export const RequestPhotoUploadInput = z.strictObject({
  inspectionId: Uuid,
  mimeType: z.enum(PHOTO_MIME_TYPES),
  sizeBytes: z.number().int().positive().max(PHOTO_MAX_BYTES),
  /** Of the file the client will upload; the server checks it on confirm. */
  contentSha256: Sha256Hex,
});
export const RequestPhotoUploadOutput = z.strictObject({
  photoId: Uuid,
  /** {org_id}/{inspection_id}/{photo_id}.{ext} */
  storagePath: z.string(),
  /** One-time signed upload URL for the private inspection-photos bucket. */
  uploadUrl: z.url(),
  expiresAt: Timestamp,
});

// confirmPhoto -------------------------------------------------------------------------
/** Registers the uploaded photo, then runs the gradeable-photo check on the server (R1, A8):
 *  focus, even lighting, glare, a visible scale reference (Anode scale card, ruler or tape
 *  measure; D6), and colour correction when the scale card is present. */
export const ConfirmPhotoInput = z.strictObject({
  photoId: Uuid,
  widthPx: z.number().int().positive().max(20000),
  heightPx: z.number().int().positive().max(20000),
  capturedAt: Timestamp.nullable().default(null),
});
export const ConfirmPhotoOutput = z.strictObject({
  photo: Photo,
  /** What to tell the person when the photo is rejected, one line per reason. */
  retakeAdvice: z.array(z.string()),
});
