import type { z } from "zod";
import type { Confidence, DefectType as DefectTypeSchema, EscalationReason, Severity as SeveritySchema } from "@/contracts/common";

export type Severity = z.infer<typeof SeveritySchema>;
export type DefectType = z.infer<typeof DefectTypeSchema>;
export type ConfidenceLevel = z.infer<typeof Confidence>;
export type Escalation = z.infer<typeof EscalationReason>;

/** The asset facts the engine reads (domain model E9). */
export interface AssetFacts {
  material: string;
  coatingStatus: "coated" | "uncoated" | "unknown";
  isInsulated: boolean;
  isPressureContaining: boolean;
  failureCouldInjure: boolean;
}
