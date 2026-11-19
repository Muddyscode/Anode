# Anode API contracts (Phase 1)

Status: **Stage 3, awaiting Michael's approval.**

Every server action the app calls, and the two outside services the server calls. The source of
truth is the Zod code in [`contracts/`](../contracts); this document explains it. Tests keep the
two in step: they fail if an action is added to one and not the other, if an enum drifts from the
database, or if a database error has no mapped error code.

Rule references (R1 to R10, D1 to D10, A1 to A42, C1 to C36, §n) point to
[`domain-model.md`](domain-model.md) and [`decisions.md`](decisions.md).

## Conventions

| Topic | Contract |
|---|---|
| Transport | Next.js server actions, called from the app. There are no public HTTP endpoints in Phase 1. |
| Authentication | Supabase Auth session cookie. No session: `UNAUTHENTICATED`. |
| Access | Each action names who may call it: `signed-in`, `member` (admin, inspector or viewer of the organisation), `writer` (inspector or admin) or `admin`. The server checks it first; row-level security checks it again in the database. |
| Validation | Every input is parsed with its Zod schema before anything else runs. Unknown keys are rejected. Text is trimmed; blank text is refused. A failure returns `VALIDATION` with `field` set to the offending path. |
| Result | Every action returns `{ ok: true, data }` or `{ ok: false, error: { code, message, field? } }` (`result()` in [`contracts/errors.ts`](../contracts/errors.ts)). Actions never throw to the client. |
| Ids | UUIDs. Create actions accept an optional client-made `id`, so a retried request does not create a duplicate (A4); a repeat with the same id returns `CONFLICT`. |
| Time | ISO 8601 timestamps with offset, stored in UTC. |
| Paging | `page: { limit (1 to 100), cursor? }` in; `{ items, nextCursor }` out, newest first. |
| Rate limits | The AI and model calls (`gradeInspection`, `confirmPhoto`) are rate-limited per user and organisation: `RATE_LIMITED` (Stage 10). |

## Errors

Every action can return the generic codes `UNAUTHENTICATED`, `FORBIDDEN`, `VALIDATION`,
`RATE_LIMITED` and `INTERNAL`; each action below lists the others it can return.

Database errors are never shown raw. `mapDbError()` turns each one into a code and a plain
message: every named constraint and every message raised by Anode's database functions has a rule
in `DB_ERROR_RULES`, and a test fails if a migration adds one without a rule. Codes marked
`INTERNAL_INVARIANT` can only be reached by a bug in Anode's own server code, never by a person's
input; they are logged and shown as a generic failure.

| Code | Means |
|---|---|
| `NOT_A_MEMBER`, `ROLE_INSUFFICIENT`, `LAST_ADMIN` | Membership and role rules (C3, §9) |
| `DUPLICATE_POINT_LABEL`, `INSPECTED_IN_FUTURE`, `ANSWER_INVALID` | Asset register and inspection input (C5, C7, C8) |
| `INSPECTION_LOCKED` | The inspection is in a signed report (C30) |
| `PHOTO_NOT_GRADEABLE`, `PHOTO_ALREADY_CHECKED`, `PHOTO_NEEDS_SCALE`, `PHOTO_ALREADY_GRADED`, `PHOTO_TOO_LARGE`, `PHOTO_UPLOAD_MISSING` | Photo rules (R1, D6, C9 to C11) |
| `GRADE_OUT_OF_RANGE`, `SEVERITY_RULE` | Grade and severity rules (C13, C15, D1) |
| `FINDING_IMMUTABLE`, `REVIEW_NOT_ALLOWED`, `REVISION_NOT_ALLOWED`, `REASON_REQUIRED` | Review rules (R9, C19 to C23, C21a) |
| `MECHANISM_NOT_ALLOWED`, `RECOMMENDATION_NOT_ALLOWED` | Mechanism and library rules (R7, R8, C17, C24) |
| `ESCALATION_IMMUTABLE` | Escalations are never removed and acknowledged once (C16) |
| `FINDINGS_UNDECIDED`, `ESCALATIONS_UNACKNOWLEDGED`, `REPORT_EMPTY`, `REPORT_PDF_MISSING` | What blocks signing (C25 to C27) |
| `REPORT_NOT_DRAFT`, `REPORT_NOT_SIGNED`, `REPORT_IMMUTABLE`, `INSPECTION_ALREADY_REPORTED`, `REPLACEMENT_INVALID` | Report lifecycle (C29, C30, C33, C34) |
| `SCOPE_NOT_SUPPORTED`, `MEASUREMENT_UNAVAILABLE` | Grading pipeline: asset outside Phase 1 scope (C32), or the measurement model failed. A failed explain step is not an error: the finding is stored without an explanation. |
| `NOT_FOUND`, `CONFLICT` | Missing or not yours; already exists |

## Grading pipeline

`gradeInspection` runs four steps on the server. Only step 3 uses a paid service.

1. **Measure.** The server sends the gradeable photo to the measurement model (outbound contract 1)
   and stores the result as a `measurement`.
2. **Grade.** The grading engine (Stage 5, plain code) maps percent area to ISO 4628-3 Ri 0 to 5 and
   to S1 to S4, applying D1 (low confidence raises one step, capped at S4). Its output must parse as
   `AiGrade`, which enforces D1 and D4 the same way the database does.
3. **Explain.** Claude receives the grade as context plus the asset, the answers, and the allowed
   mechanisms and recommendations (outbound contract 2). Its reply must parse as `ExplainOutput`,
   which has no grade, severity or confidence fields, and then pass `checkExplainOutput()` against the
   allowed lists. Anything else is discarded, and the finding is stored without an explanation.
4. **Store.** One draft AI finding with its hypotheses and recommendations, in one transaction. The
   database adds the escalations that follow from the data (S4, injury risk, insulation, pitting on
   pressure equipment, suspected cracking).

### Outbound contract 1: measurement model

`POST {MEASUREMENT_API_URL}/measure`, server to server, authenticated with a shared secret header.
Hosting is decided in Stage 6.

| | Schema | Fields |
|---|---|---|
| Request | `MeasureRequest` | `imageUrl` (short-lived signed URL), `widthPx`, `heightPx`, `mmPerPx` |
| Response | `MeasureResponse` | `modelName`, `modelVersion`, `percentAreaRusted` (0 to 100), `outline` (GeoJSON MultiPolygon in pixels, A12), `modelConfidence` (0 to 1) |

No depth, thickness or wall-loss values exist in the contract (R6). A timeout, a non-2xx reply or a
reply that does not parse returns `MEASUREMENT_UNAVAILABLE` and stores nothing.

### Outbound contract 2: Claude explain step

Called through the Claude API with structured output. This is the only paid service (D10).

| | Schema | Fields |
|---|---|---|
| Request | `ExplainInput` | the grade (context only), measurement summary, asset facts, answers with ids, allowed mechanisms, allowed recommendations |
| Response | `ExplainOutput` | up to 3 `hypotheses` (mechanism, visual evidence, cited answer ids), `recommendationCodes` from the library, `additionalEscalations` (only `suspected_cracking`, A30), `possibleStaining`, `summary` |

## Decisions this stage assumes

- **Server actions only.** The measurement model is called by Anode's server, so it is an outbound
  contract, not an endpoint Anode exposes.
- **Signing and voiding use the service role** inside `signReport` and `voidReport`. Clients never call
  `sign_report` or `void_report` (C28, C33).
- **Atomic multi-row writes.** `reviewFinding` (edit), `addInspectorFinding`, `reviseFinding` and the
  store step of `gradeInspection` each write several rows. Each runs as one database transaction
  through a database function added when the action is built (Stages 7 to 9), so a failure never
  leaves half a finding.
- **No invitations in Phase 1** (A2): membership management is listing members and changing roles.
- **Free tiers except the AI** (D10): nothing in these contracts needs a paid service except the
  explain step.

## Session and organisation

Schemas: [`contracts/session.ts`](../contracts/session.ts).

### getSession

Who is signed in and which organisations they belong to, with their role in each.

Input `GetSessionInput` · Output `GetSessionOutput`

| | |
|---|---|
| Access | signed-in |
| Errors | generic only |
| Rules | A2 |

### updateProfile

Changes the signed-in person's display name or qualification. Both are printed on reports they sign (A21).

Input `UpdateProfileInput` · Output `UpdateProfileOutput`

| | |
|---|---|
| Access | signed-in |
| Errors | generic only |
| Rules | A21 |

### renameOrganisation

Renames an organisation. The demo flag cannot be changed through the API.

Input `RenameOrganisationInput` · Output `RenameOrganisationOutput`

| | |
|---|---|
| Access | admin |
| Errors | `NOT_FOUND` |
| Rules | §9 |

### listMembers

Members of an organisation and their roles.

Input `ListMembersInput` · Output `ListMembersOutput`

| | |
|---|---|
| Access | member |
| Errors | generic only |
| Rules | §9 |

### changeMemberRole

Changes a member's role. An organisation always keeps at least one admin. Phase 1 has no invitations (A2); a person joins by signing up.

Input `ChangeMemberRoleInput` · Output `ChangeMemberRoleOutput`

| | |
|---|---|
| Access | admin |
| Errors | `NOT_FOUND`, `LAST_ADMIN` |
| Rules | §9 |

## Reference data

Schemas: [`contracts/reference.ts`](../contracts/reference.ts).

### getReferenceData

Standard, severity scale with its R3 actions, mechanisms, the active recommendation library and the active context questions. Loaded once per session and cached.

Input `GetReferenceDataInput` · Output `GetReferenceDataOutput`

| | |
|---|---|
| Access | signed-in |
| Errors | generic only |
| Rules | R3, R7, R8, C2 |

## Asset register

Schemas: [`contracts/assets.ts`](../contracts/assets.ts).

### listAssets

Assets in an organisation, newest first; archived ones only on request. `gradeable` tells the UI whether Phase 1 can grade the asset (coated steel, C32).

Input `ListAssetsInput` · Output `ListAssetsOutput`

| | |
|---|---|
| Access | member |
| Errors | generic only |
| Rules | none |

### getAsset

One asset and its inspection points, each with its last inspection date.

Input `GetAssetInput` · Output `GetAssetOutput`

| | |
|---|---|
| Access | member |
| Errors | `NOT_FOUND` |
| Rules | none |

### createAsset

Adds an asset. The three escalation flags (insulated, pressure-containing, failure could injure) must be answered; there are no defaults (A10).

Input `CreateAssetInput` · Output `CreateAssetOutput`

| | |
|---|---|
| Access | writer |
| Errors | `CONFLICT` |
| Rules | A10, C6 |

### updateAsset

Changes an asset's details. Changing an escalation flag affects findings graded from then on; existing findings keep the escalations they were given.

Input `UpdateAssetInput` · Output `UpdateAssetOutput`

| | |
|---|---|
| Access | writer |
| Errors | `NOT_FOUND` |
| Rules | C6 |

### archiveAsset

Archives or restores an asset. Assets are never deleted (section 2).

Input `ArchiveAssetInput` · Output `ArchiveAssetOutput`

| | |
|---|---|
| Access | writer |
| Errors | `NOT_FOUND` |
| Rules | §2 |

### createPoint

Adds an inspection point to an asset. Labels are unique per asset, ignoring case (C5).

Input `CreatePointInput` · Output `CreatePointOutput`

| | |
|---|---|
| Access | writer |
| Errors | `NOT_FOUND`, `DUPLICATE_POINT_LABEL`, `CONFLICT` |
| Rules | C5 |

### updatePoint

Changes a point's label or description.

Input `UpdatePointInput` · Output `UpdatePointOutput`

| | |
|---|---|
| Access | writer |
| Errors | `NOT_FOUND`, `DUPLICATE_POINT_LABEL` |
| Rules | C5 |

### archivePoint

Archives or restores a point.

Input `ArchivePointInput` · Output `ArchivePointOutput`

| | |
|---|---|
| Access | writer |
| Errors | `NOT_FOUND` |
| Rules | §2 |

## Inspections and photos

Schemas: [`contracts/inspections.ts`](../contracts/inspections.ts).

### listInspections

Inspections in an organisation, newest first, filterable by status, asset or point. Each row carries its worst severity and open-escalation count.

Input `ListInspectionsInput` · Output `ListInspectionsOutput`

| | |
|---|---|
| Access | member |
| Errors | generic only |
| Rules | none |

### getInspection

Everything about one inspection: answers, every photo (rejected retakes included, A6), findings with their measurements, mechanisms and recommendations, and escalations. `revisable` is true after its report was voided (C21a).

Input `GetInspectionInput` · Output `GetInspectionOutput`

| | |
|---|---|
| Access | member |
| Errors | `NOT_FOUND` |
| Rules | R6, C21a |

### createInspection

Starts a draft inspection at a point. `inspectedAt` defaults to now and cannot be in the future (C7). Any inspector in the organisation may record it (A22).

Input `CreateInspectionInput` · Output `CreateInspectionOutput`

| | |
|---|---|
| Access | writer |
| Errors | `NOT_FOUND`, `INSPECTED_IN_FUTURE`, `CONFLICT` |
| Rules | C3, C7 |

### updateInspection

Changes the date or notes while the inspection is not in a signed report (C30).

Input `UpdateInspectionInput` · Output `UpdateInspectionOutput`

| | |
|---|---|
| Access | writer |
| Errors | `NOT_FOUND`, `INSPECTED_IN_FUTURE`, `INSPECTION_LOCKED` |
| Rules | C7, C30 |

### saveContextAnswers

Saves answers to the context questions, one per question. The server checks each value against the question's type and options before writing (C8).

Input `SaveContextAnswersInput` · Output `SaveContextAnswersOutput`

| | |
|---|---|
| Access | writer |
| Errors | `NOT_FOUND`, `ANSWER_INVALID`, `INSPECTION_LOCKED` |
| Rules | C8, C30 |

### requestPhotoUpload

Reserves a photo id and returns a one-time signed upload URL to the private `inspection-photos` bucket at `{org}/{inspection}/{photo}.{ext}`. Refused when the inspection already has a gradeable photo (C10a).

Input `RequestPhotoUploadInput` · Output `RequestPhotoUploadOutput`

| | |
|---|---|
| Access | writer |
| Errors | `NOT_FOUND`, `PHOTO_TOO_LARGE`, `PHOTO_ALREADY_GRADED`, `INSPECTION_LOCKED` |
| Rules | C10a, C30, §9 |

### confirmPhoto

Registers the uploaded photo and runs the gradeable-photo check on the server (R1, A8): focus, even light, glare, and a scale reference in view: the Anode scale card (preferred, enables colour correction), a ruler or a tape measure. Coins are not accepted (D6). Location data is stripped (A7). A rejected photo is kept and `retakeAdvice` says what to fix.

Input `ConfirmPhotoInput` · Output `ConfirmPhotoOutput`

| | |
|---|---|
| Access | writer |
| Errors | `NOT_FOUND`, `PHOTO_UPLOAD_MISSING`, `PHOTO_ALREADY_CHECKED`, `PHOTO_ALREADY_GRADED`, `INSPECTION_LOCKED` |
| Rules | R1, D6, A6, A7, A8, C9, C10, C10a, C10b |

## Grading

Schemas: [`contracts/findings.ts`](../contracts/findings.ts).

### gradeInspection

Runs the pipeline on the inspection's gradeable photo: measure, grade, explain, store. The result is one draft AI finding. Escalations that follow from the data are added by the database (R5, D2). If the explain step fails or returns anything outside its contract, the finding is stored without mechanisms or recommendations rather than with untrusted ones. Refuses assets Phase 1 cannot grade (`SCOPE_NOT_SUPPORTED`, C32).

Input `GradeInspectionInput` · Output `GradeInspectionOutput`

| | |
|---|---|
| Access | writer |
| Errors | `NOT_FOUND`, `PHOTO_NOT_GRADEABLE`, `SCOPE_NOT_SUPPORTED`, `MEASUREMENT_UNAVAILABLE`, `INSPECTION_LOCKED` |
| Rules | R1, R2, R4, R5, R6, R7, R8, D1, D2, D4, C12, C13, C15, C16b, C19a, C32 |

## Review and escalation

Schemas: [`contracts/review.ts`](../contracts/review.ts).

### reviewFinding

The inspector's decision on a draft AI finding (R9). `accept`; `reject` with a reason; or `edit` with a reason and the inspector's own finding, which supersedes the AI one while the AI's original is kept as feedback (A17). An edit writes both rows in one transaction.

Input `ReviewFindingInput` · Output `ReviewFindingOutput`

| | |
|---|---|
| Access | writer |
| Errors | `NOT_FOUND`, `REVIEW_NOT_ALLOWED`, `REASON_REQUIRED`, `GRADE_OUT_OF_RANGE`, `MECHANISM_NOT_ALLOWED`, `RECOMMENDATION_NOT_ALLOWED`, `INSPECTION_LOCKED` |
| Rules | R9, D3, A17, A18, C20, C21, C22, C23 |

### addInspectorFinding

Records a finding the AI missed, on the inspection's gradeable photo. It is accepted as written; the inspector's judgement needs no rule adjustment (D3).

Input `AddInspectorFindingInput` · Output `AddInspectorFindingOutput`

| | |
|---|---|
| Access | writer |
| Errors | `NOT_FOUND`, `PHOTO_NOT_GRADEABLE`, `GRADE_OUT_OF_RANGE`, `MECHANISM_NOT_ALLOWED`, `RECOMMENDATION_NOT_ALLOWED`, `INSPECTION_LOCKED` |
| Rules | R1, R5, D2, D3, A13, C20 |

### reviseFinding

After a report is voided, corrects an accepted finding by adding a superseding inspector finding with a reason (C21a, D7). The earlier finding is kept.

Input `ReviseFindingInput` · Output `ReviseFindingOutput`

| | |
|---|---|
| Access | writer |
| Errors | `NOT_FOUND`, `REVISION_NOT_ALLOWED`, `REASON_REQUIRED`, `GRADE_OUT_OF_RANGE`, `MECHANISM_NOT_ALLOWED`, `RECOMMENDATION_NOT_ALLOWED`, `INSPECTION_LOCKED` |
| Rules | D7, A38, C21a |

### raiseEscalation

An inspector adds an escalation to a finding. Escalations are never removed (R5).

Input `RaiseEscalationInput` · Output `RaiseEscalationOutput`

| | |
|---|---|
| Access | writer |
| Errors | `NOT_FOUND`, `CONFLICT`, `INSPECTION_LOCKED` |
| Rules | R5, C16c |

### acknowledgeEscalation

An inspector records that a qualified person has seen the escalation, with a note (A34). Once only; audited (D8).

Input `AcknowledgeEscalationInput` · Output `AcknowledgeEscalationOutput`

| | |
|---|---|
| Access | writer |
| Errors | `NOT_FOUND`, `ESCALATION_IMMUTABLE`, `INSPECTION_LOCKED` |
| Rules | R5, D8, A34, C16 |

## Reports

Schemas: [`contracts/reports.ts`](../contracts/reports.ts).

### listReports

Reports in an organisation. Viewers see signed and void reports only.

Input `ListReportsInput` · Output `ListReportsOutput`

| | |
|---|---|
| Access | member |
| Errors | generic only |
| Rules | §9 |

### getReport

One report. For a draft, `readiness` lists what still blocks signing: undecided findings, unacknowledged escalations, inspections in other reports.

Input `GetReportInput` · Output `GetReportOutput`

| | |
|---|---|
| Access | member |
| Errors | `NOT_FOUND` |
| Rules | §9 |

### createReport

Creates a draft report over one or more inspections. `replacesReportId` reissues a voided report (C34). An inspection is in at most one report that is not void (C29).

Input `CreateReportInput` · Output `CreateReportOutput`

| | |
|---|---|
| Access | writer |
| Errors | `NOT_FOUND`, `INSPECTION_ALREADY_REPORTED`, `REPLACEMENT_INVALID`, `CONFLICT` |
| Rules | A20, C29, C34 |

### updateDraftReport

Renames a draft report or adds and removes inspections.

Input `UpdateDraftReportInput` · Output `UpdateDraftReportOutput`

| | |
|---|---|
| Access | writer |
| Errors | `NOT_FOUND`, `REPORT_NOT_DRAFT`, `INSPECTION_ALREADY_REPORTED` |
| Rules | C29, C30 |

### deleteDraftReport

Deletes a draft report. Signed and void reports are never deleted.

Input `DeleteDraftReportInput` · Output `DeleteDraftReportOutput`

| | |
|---|---|
| Access | writer |
| Errors | `NOT_FOUND`, `REPORT_IMMUTABLE` |
| Rules | C30 |

### signReport

Signs as the signed-in inspector. The server checks readiness, renders the PDF with the "screening only" disclaimer (C31), stores it, then calls `sign_report` with the PDF's SHA-256 using the service role (C28). The person must confirm the signature statement explicitly.

Input `SignReportInput` · Output `SignReportOutput`

| | |
|---|---|
| Access | writer |
| Errors | `NOT_FOUND`, `REPORT_NOT_DRAFT`, `REPORT_EMPTY`, `FINDINGS_UNDECIDED`, `ESCALATIONS_UNACKNOWLEDGED`, `INSPECTION_ALREADY_REPORTED`, `REPORT_PDF_MISSING` |
| Rules | R5, R9, D8, C25, C26, C27, C28, C31 |

### voidReport

Voids a signed report with a reason, through `void_report` (C33). The report and its PDF are kept unchanged; its inspections are released so findings can be revised and a replacement report signed (A38).

Input `VoidReportInput` · Output `VoidReportOutput`

| | |
|---|---|
| Access | writer |
| Errors | `NOT_FOUND`, `REPORT_NOT_SIGNED`, `REASON_REQUIRED` |
| Rules | D7, D8, A38, C33 |

### getReportDownloadUrl

A short-lived signed URL for a signed or void report's PDF, with its SHA-256 so the file can be verified.

Input `GetReportDownloadUrlInput` · Output `GetReportDownloadUrlOutput`

| | |
|---|---|
| Access | member |
| Errors | `NOT_FOUND` |
| Rules | §9 |

## Audit

Schemas: [`contracts/audit.ts`](../contracts/audit.ts).

### listAuditEvents

The append-only audit log: signing, voiding, escalation acknowledgements, reviews and revisions (D8). Inspectors and admins only (A41).

Input `ListAuditEventsInput` · Output `ListAuditEventsOutput`

| | |
|---|---|
| Access | writer |
| Errors | generic only |
| Rules | D8, A41 |

