// Reference data (domain model E4 to E8): read-only for everyone signed in.

import { z } from "zod";
import { AnswerType, EscalationReason, GradeScale, Severity, Uuid } from "./common";

export const Standard = z.strictObject({
  id: Uuid,
  code: z.string(),
  edition: z.string(),
  title: z.string(),
  gradeScale: GradeScale,
  gradeMin: z.number().int(),
  gradeMax: z.number().int(),
});

export const SeverityLevel = z.strictObject({
  code: Severity,
  name: z.string(),
  action: z.string(),
  requiresEscalation: z.boolean(),
});

export const Mechanism = z.strictObject({
  code: z.string(),
  name: z.string(),
  /** MIC: never ranked first (C17). */
  possibilityOnly: z.boolean(),
  escalationReason: EscalationReason.nullable(),
});

export const Recommendation = z.strictObject({
  code: z.string(),
  version: z.number().int().min(1),
  text: z.string(),
  minSeverity: Severity.nullable(),
});

export const ContextQuestion = z.strictObject({
  key: z.string(),
  prompt: z.string(),
  answerType: AnswerType,
  options: z.array(z.string()).nullable(),
  sortOrder: z.number().int(),
});

// getReferenceData ------------------------------------------------------------------
export const GetReferenceDataInput = z.strictObject({});
export const GetReferenceDataOutput = z.strictObject({
  standards: z.array(Standard),
  severityLevels: z.array(SeverityLevel).length(4),
  mechanisms: z.array(Mechanism),
  /** Active library versions only (R8). */
  recommendations: z.array(Recommendation),
  /** Active questions only, in display order. */
  contextQuestions: z.array(ContextQuestion),
});
