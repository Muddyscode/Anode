// Severity as the design system shows it (README, "Severity pipe markers").
// Codes match the database and contracts (S1 to S4, business rule R3).

export type Severity = "S1" | "S2" | "S3" | "S4";

export const SEVERITY: Record<Severity, { name: string; action: string; fill: string; text: string; needleAngle: number }> = {
  S1: { name: "Cosmetic", action: "Monitor at the normal interval", fill: "var(--sev-1)", text: "var(--on-sev-1)", needleAngle: 22.5 },
  S2: { name: "Developing", action: "Plan maintenance, re-inspect sooner", fill: "var(--sev-2)", text: "var(--on-sev-2)", needleAngle: 67.5 },
  S3: { name: "Significant", action: "Schedule repair, measure thickness", fill: "var(--sev-3)", text: "var(--on-sev-3)", needleAngle: 112.5 },
  S4: { name: "Critical", action: "Stop and escalate now", fill: "var(--sev-4)", text: "var(--on-sev-4)", needleAngle: 157.5 },
};

export const SEVERITIES: readonly Severity[] = ["S1", "S2", "S3", "S4"];
