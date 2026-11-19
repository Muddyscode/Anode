// The grading engine against Michael's rules (D1, D2, D4, D12, R4, R5, C32), at every boundary.
import { describe, expect, it } from "vitest";
import { AiGrade } from "@/contracts/findings";
import { checkScope, confidenceFromScore, gradeMeasurement, requiredEscalations, riFromPercent, rulesSeverity } from "./grade";
import { DEFECT_SEVERITY_FLOOR, GRADING_RULES_VERSION, RI_SEVERITY } from "./rules";
import type { DefectType, Severity } from "./types";

const EPS = 1e-9;
const SEVERITIES: Severity[] = ["S1", "S2", "S3", "S4"];
const DEFECTS: DefectType[] = ["rusting", "pitting", "suspected_cracking", "coating_breakdown", "other"];

describe("riFromPercent: D12 cut-offs, rounding up", () => {
  it.each([
    [0, 0],
    [EPS, 1],
    [0.05, 1],
    [0.05 + EPS, 2],
    [0.5, 2],
    [0.5 + EPS, 3],
    [1, 3],
    [1 + EPS, 4],
    [8, 4],
    [8 + EPS, 5],
    [45, 5],
    [100, 5],
  ])("%s%% rusted is Ri %s", (pct, ri) => {
    expect(riFromPercent(pct)).toBe(ri);
  });

  it.each([-EPS, -1, 100 + EPS, Number.NaN, Number.POSITIVE_INFINITY])("refuses %s", (pct) => {
    expect(() => riFromPercent(pct)).toThrow(RangeError);
  });

  it("never grades down as rust increases", () => {
    let last = 0;
    for (let pct = 0; pct <= 100; pct += 0.01) {
      const ri = riFromPercent(Math.min(100, pct));
      expect(ri).toBeGreaterThanOrEqual(last);
      last = ri;
    }
  });
});

describe("confidenceFromScore: D12 thresholds", () => {
  it.each([
    [1, "high"],
    [0.85, "high"],
    [0.85 - EPS, "medium"],
    [0.6, "medium"],
    [0.6 - EPS, "low"],
    [0, "low"],
  ])("%s is %s", (score, level) => {
    expect(confidenceFromScore(score)).toBe(level);
  });

  it.each([-EPS, 1 + EPS, Number.NaN])("refuses %s", (score) => {
    expect(() => confidenceFromScore(score)).toThrow(RangeError);
  });
});

describe("rulesSeverity: D12 Ri mapping and defect floors", () => {
  const expected: Record<number, Record<DefectType, Severity>> = {
    0: { rusting: "S1", coating_breakdown: "S1", other: "S1", pitting: "S3", suspected_cracking: "S4" },
    1: { rusting: "S1", coating_breakdown: "S1", other: "S1", pitting: "S3", suspected_cracking: "S4" },
    2: { rusting: "S2", coating_breakdown: "S2", other: "S2", pitting: "S3", suspected_cracking: "S4" },
    3: { rusting: "S2", coating_breakdown: "S2", other: "S2", pitting: "S3", suspected_cracking: "S4" },
    4: { rusting: "S3", coating_breakdown: "S3", other: "S3", pitting: "S3", suspected_cracking: "S4" },
    5: { rusting: "S4", coating_breakdown: "S4", other: "S4", pitting: "S4", suspected_cracking: "S4" },
  };
  for (const ri of [0, 1, 2, 3, 4, 5]) {
    for (const defect of DEFECTS) {
      it(`Ri ${ri} ${defect} is ${expected[ri]![defect]}`, () => {
        expect(rulesSeverity(ri, defect)).toBe(expected[ri]![defect]);
      });
    }
  }

  it.each([-1, 6, 2.5])("refuses Ri %s", (ri) => {
    expect(() => rulesSeverity(ri, "rusting")).toThrow(RangeError);
  });

  it("matches the decided tables", () => {
    expect(RI_SEVERITY).toEqual({ 0: "S1", 1: "S1", 2: "S2", 3: "S2", 4: "S3", 5: "S4" });
    expect(DEFECT_SEVERITY_FLOOR.pitting).toBe("S3");
    expect(DEFECT_SEVERITY_FLOOR.suspected_cracking).toBe("S4");
  });
});

describe("gradeMeasurement", () => {
  it("grades a measurement end to end", () => {
    expect(gradeMeasurement({ percentAreaRusted: 1.02, modelConfidence: 0.9, defectType: "rusting" })).toEqual({
      standardCode: "ISO 4628-3",
      gradeValue: 4,
      rulesSeverity: "S3",
      severity: "S3",
      confidence: "high",
      severityRaisedReason: null,
      defectType: "rusting",
      gradingRulesVersion: GRADING_RULES_VERSION,
    });
  });

  it.each([
    [0, "S1", "S2"],
    [0.3, "S2", "S3"],
    [5, "S3", "S4"],
    [50, "S4", "S4"],
  ] as const)("D1: low confidence at %s%% raises %s to %s, capped at S4", (pct, base, raised) => {
    const g = gradeMeasurement({ percentAreaRusted: pct, modelConfidence: 0.4, defectType: "rusting" });
    expect(g.rulesSeverity).toBe(base);
    expect(g.severity).toBe(raised);
    expect(g.severityRaisedReason === null).toBe(base === raised);
  });

  it("R4: an AI grade with low confidence is never S1", () => {
    for (let pct = 0; pct <= 100; pct += 0.25) {
      for (const defectType of DEFECTS) {
        expect(gradeMeasurement({ percentAreaRusted: pct, modelConfidence: 0.1, defectType }).severity).not.toBe("S1");
      }
    }
  });

  it("D4: medium confidence keeps S1", () => {
    expect(gradeMeasurement({ percentAreaRusted: 0.01, modelConfidence: 0.7, defectType: "rusting" }).severity).toBe("S1");
  });

  it("every output parses as the AiGrade contract", () => {
    for (const pct of [0, 0.05, 0.5, 1, 8, 100]) {
      for (const conf of [0.1, 0.7, 0.95]) {
        for (const defectType of DEFECTS) {
          expect(AiGrade.safeParse(gradeMeasurement({ percentAreaRusted: pct, modelConfidence: conf, defectType })).success).toBe(true);
        }
      }
    }
  });

  it("same numbers, same grade", () => {
    const input = { percentAreaRusted: 3.3, modelConfidence: 0.72, defectType: "pitting" as const };
    expect(gradeMeasurement(input)).toEqual(gradeMeasurement(input));
  });
});

describe("checkScope: C32 coated steel only", () => {
  it.each(["carbon_steel", "low_alloy_steel", "galvanised_steel"])("grades coated %s", (material) => {
    expect(checkScope({ material, coatingStatus: "coated" })).toEqual({ ok: true });
  });
  it.each(["stainless_steel", "cast_iron", "other", "unknown"])("refuses %s", (material) => {
    expect(checkScope({ material, coatingStatus: "coated" }).ok).toBe(false);
  });
  it.each(["uncoated", "unknown"] as const)("refuses %s steel", (coatingStatus) => {
    expect(checkScope({ material: "carbon_steel", coatingStatus })).toEqual({
      ok: false,
      reason: "Phase 1 grades coated steel only, on ISO 4628-3.",
    });
  });
});

describe("requiredEscalations: rule 5 and D2", () => {
  const plain = { isInsulated: false, isPressureContaining: false, failureCouldInjure: false };

  it("none for an ordinary S2 rust finding", () => {
    expect(requiredEscalations({ severity: "S2", defectType: "rusting", asset: plain })).toEqual([]);
  });
  it.each(SEVERITIES)("S4 always escalates; %s", (severity) => {
    expect(requiredEscalations({ severity, defectType: "rusting", asset: plain }).includes("severity_s4")).toBe(severity === "S4");
  });
  it("D2: injury-risk assets escalate every finding, S1 included", () => {
    expect(requiredEscalations({ severity: "S1", defectType: "rusting", asset: { ...plain, failureCouldInjure: true } })).toEqual(["injury_risk"]);
  });
  it("insulated assets, or CUI ranked, escalate for suspected CUI", () => {
    expect(requiredEscalations({ severity: "S1", defectType: "rusting", asset: { ...plain, isInsulated: true } })).toEqual(["suspected_cui"]);
    expect(requiredEscalations({ severity: "S1", defectType: "rusting", asset: plain, rankedMechanisms: ["cui"] })).toEqual(["suspected_cui"]);
  });
  it("pitting on pressure equipment escalates, by defect or by ranked mechanism", () => {
    const pressure = { ...plain, isPressureContaining: true };
    expect(requiredEscalations({ severity: "S3", defectType: "pitting", asset: pressure })).toEqual(["pressure_pitting_or_wall_loss"]);
    expect(requiredEscalations({ severity: "S2", defectType: "rusting", asset: pressure, rankedMechanisms: ["pitting"] })).toEqual([
      "pressure_pitting_or_wall_loss",
    ]);
    expect(requiredEscalations({ severity: "S2", defectType: "rusting", asset: pressure })).toEqual([]);
  });
  it("suspected cracking escalates, and is S4", () => {
    const g = gradeMeasurement({ percentAreaRusted: 0.01, modelConfidence: 0.9, defectType: "suspected_cracking" });
    expect(g.severity).toBe("S4");
    expect(requiredEscalations({ severity: g.severity, defectType: g.defectType, asset: plain })).toEqual(["severity_s4", "suspected_cracking"]);
  });
});
