// The business rules the contracts enforce, tested at their boundaries.
import { describe, expect, it } from "vitest";
import { Confidence, ScaleReference, Severity, expectedAiSeverity } from "./common";
import { CreateAssetInput, UpdateAssetInput } from "./assets";
import { AiGrade, ExplainInput, ExplainOutput, MeasureResponse, checkExplainOutput } from "./findings";
import { RequestPhotoUploadInput, SaveContextAnswersInput } from "./inspections";
import { CreateReportInput, SignReportInput, VoidReportInput } from "./reports";
import { AcknowledgeEscalationInput, InspectorFindingFields, ReviewFindingInput } from "./review";

const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

describe("D1, D4: severity and confidence for AI findings", () => {
  const cases: [string, string, string][] = [
    ["S1", "low", "S2"],
    ["S2", "low", "S3"],
    ["S3", "low", "S4"],
    ["S4", "low", "S4"],
    ["S1", "medium", "S1"],
    ["S1", "high", "S1"],
    ["S3", "medium", "S3"],
  ];
  it.each(cases)("rules %s with %s confidence gives %s", (rules, conf, expected) => {
    expect(expectedAiSeverity(Severity.parse(rules), Confidence.parse(conf))).toBe(expected);
  });

  const grade = (over: Partial<Record<string, unknown>>) => ({
    standardCode: "ISO 4628-3",
    gradeValue: 2,
    rulesSeverity: "S1",
    severity: "S1",
    confidence: "high",
    severityRaisedReason: null,
    defectType: "rusting",
    gradingRulesVersion: "1",
    ...over,
  });

  it("R4: an AI grade with low confidence is never S1", () => {
    expect(AiGrade.safeParse(grade({ confidence: "low" })).success).toBe(false);
  });
  it("D1: low confidence raises exactly one step, with a reason", () => {
    expect(AiGrade.safeParse(grade({ confidence: "low", severity: "S2", severityRaisedReason: "Low confidence." })).success).toBe(true);
    expect(AiGrade.safeParse(grade({ confidence: "low", severity: "S3", severityRaisedReason: "Too far." })).success).toBe(false);
  });
  it("R4: a raise always says why", () => {
    expect(AiGrade.safeParse(grade({ confidence: "low", severity: "S2" })).success).toBe(false);
  });
  it("D4: medium confidence does not block S1", () => {
    expect(AiGrade.safeParse(grade({ confidence: "medium" })).success).toBe(true);
  });
  it("C13: Ri is 0 to 5", () => {
    expect(AiGrade.safeParse(grade({ gradeValue: 6 })).success).toBe(false);
    expect(AiGrade.safeParse(grade({ gradeValue: -1 })).success).toBe(false);
  });
  it("D9: Phase 1 grades on ISO 4628-3 only", () => {
    expect(AiGrade.safeParse(grade({ standardCode: "ASTM D610" })).success).toBe(false);
  });
});

describe("D3: inspector findings", () => {
  const base = { defectType: "rusting", gradeValue: 0, severity: "S1", confidence: "low", summary: "Light bloom only." };
  it("an inspector may record S1 with low confidence", () => {
    expect(InspectorFindingFields.safeParse(base).success).toBe(true);
  });
  it("R7: at most three mechanisms", () => {
    const h = { mechanismCode: "uniform", visualEvidence: "Even rust." };
    expect(InspectorFindingFields.safeParse({ ...base, hypotheses: [h, h, h, h] }).success).toBe(false);
  });
});

describe("R1, D6: photos", () => {
  it("coins are not a scale reference", () => {
    expect(ScaleReference.safeParse("coin").success).toBe(false);
    expect(ScaleReference.options).toEqual(["anode_scale_card", "ruler", "tape_measure", "none"]);
  });
  it("uploads are images within the bucket limit", () => {
    const ok = { inspectionId: id(1), mimeType: "image/jpeg", sizeBytes: 1000, contentSha256: "a".repeat(64) };
    expect(RequestPhotoUploadInput.safeParse(ok).success).toBe(true);
    expect(RequestPhotoUploadInput.safeParse({ ...ok, mimeType: "application/pdf" }).success).toBe(false);
    expect(RequestPhotoUploadInput.safeParse({ ...ok, sizeBytes: 21 * 1024 * 1024 }).success).toBe(false);
  });
});

describe("R6: no depth or thickness from a photo", () => {
  it("the measurement contract has no depth, thickness or wall-loss fields", () => {
    expect(Object.keys(MeasureResponse.shape).filter((k) => /depth|thickness|wall/i.test(k))).toEqual([]);
  });
});

describe("explain step (P-AI, R7, R8, C17, C19a)", () => {
  const output = {
    hypotheses: [{ mechanismCode: "uniform", visualEvidence: "Even rust.", evidenceAnswerIds: [] }],
    recommendationCodes: ["monitor"],
    additionalEscalations: [],
    possibleStaining: false,
    summary: "Uniform surface rust.",
  };
  const input = ExplainInput.parse({
    grade: { gradeValue: 2, severity: "S2", confidence: "high" },
    measurement: { percentAreaRusted: 0.5, modelConfidence: 0.9 },
    asset: { assetType: "tank", material: "carbon_steel", coatingStatus: "coated", environment: "atmospheric_marine", isInsulated: false },
    answers: [],
    allowedMechanisms: [
      { code: "uniform", name: "Uniform corrosion", possibilityOnly: false },
      { code: "mic", name: "MIC", possibilityOnly: true },
    ],
    allowedRecommendations: [{ code: "monitor", text: "Monitor." }],
  });

  it("accepts a well-formed explanation", () => {
    expect(ExplainOutput.safeParse(output).success).toBe(true);
    expect(checkExplainOutput(ExplainOutput.parse(output), input)).toEqual([]);
  });
  it.each(["severity", "gradeValue", "confidence", "rulesSeverity"])("cannot carry a grade field: %s", (key) => {
    expect(ExplainOutput.safeParse({ ...output, [key]: "S1" }).success).toBe(false);
  });
  it("R7: at most three mechanisms, each once", () => {
    const h = output.hypotheses[0];
    expect(ExplainOutput.safeParse({ ...output, hypotheses: [h, h] }).success).toBe(false);
    const four = ["a", "b", "c", "d"].map((c) => ({ ...h, mechanismCode: c }));
    expect(ExplainOutput.safeParse({ ...output, hypotheses: four }).success).toBe(false);
  });
  it("cannot remove escalations or add any but suspected cracking (A30)", () => {
    expect(ExplainOutput.safeParse({ ...output, additionalEscalations: ["injury_risk"] }).success).toBe(false);
  });
  it("R8 / C17: only allowed mechanisms and library recommendations; MIC never first", () => {
    const bad = ExplainOutput.parse({
      ...output,
      hypotheses: [{ mechanismCode: "mic", visualEvidence: "Slime.", evidenceAnswerIds: [] }],
      recommendationCodes: ["free_text_advice"],
    });
    expect(checkExplainOutput(bad, input)).toEqual([
      "MIC cannot be ranked first",
      "recommendation free_text_advice is not in the library",
    ]);
  });
});

describe("R9, D7: review, escalation and reports need reasons", () => {
  it("accept needs no reason; reject and edit do (A18)", () => {
    expect(ReviewFindingInput.safeParse({ findingId: id(1), decision: "accept" }).success).toBe(true);
    expect(ReviewFindingInput.safeParse({ findingId: id(1), decision: "reject" }).success).toBe(false);
    expect(ReviewFindingInput.safeParse({ findingId: id(1), decision: "reject", reason: "  " }).success).toBe(false);
    expect(ReviewFindingInput.safeParse({ findingId: id(1), decision: "edit", reason: "Deeper pits." }).success).toBe(false);
  });
  it("acknowledging an escalation needs a note (C16)", () => {
    expect(AcknowledgeEscalationInput.safeParse({ escalationId: id(1), note: "" }).success).toBe(false);
  });
  it("voiding needs a reason (C33)", () => {
    expect(VoidReportInput.safeParse({ reportId: id(1), reason: " " }).success).toBe(false);
  });
  it("signing needs an explicit confirmation", () => {
    expect(SignReportInput.safeParse({ reportId: id(1), confirmStatement: false }).success).toBe(false);
  });
  it("a report covers at least one inspection, each once (C27)", () => {
    expect(CreateReportInput.safeParse({ orgId: id(1), title: "T", inspectionIds: [] }).success).toBe(false);
    expect(CreateReportInput.safeParse({ orgId: id(1), title: "T", inspectionIds: [id(2), id(2)] }).success).toBe(false);
  });
});

describe("asset register and answers", () => {
  const asset = {
    orgId: id(1),
    name: "Tank T2",
    assetType: "tank",
    material: "carbon_steel",
    coatingStatus: "coated",
    environment: "atmospheric_marine",
    isInsulated: false,
    isPressureContaining: false,
    failureCouldInjure: true,
  };
  it("A10: the escalation flags must be answered", () => {
    expect(CreateAssetInput.safeParse(asset).success).toBe(true);
    const missing: Partial<typeof asset> = { ...asset };
    delete missing.failureCouldInjure;
    expect(CreateAssetInput.safeParse(missing).success).toBe(false);
  });
  it("C6: latitude and longitude come together", () => {
    expect(CreateAssetInput.safeParse({ ...asset, latitude: 4.8 }).success).toBe(false);
    expect(UpdateAssetInput.safeParse({ assetId: id(1), patch: { longitude: 7 } }).success).toBe(false);
  });
  it("unknown keys are rejected", () => {
    expect(CreateAssetInput.safeParse({ ...asset, isDemo: true }).success).toBe(false);
  });
  it("each question is answered once", () => {
    const a = { questionKey: "standing_water", value: true };
    expect(SaveContextAnswersInput.safeParse({ inspectionId: id(1), answers: [a, a] }).success).toBe(false);
  });
});
