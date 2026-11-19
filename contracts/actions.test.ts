// docs/api.md and the action registry must describe the same actions, access and errors,
// and every rule an action cites must exist in the domain model or the decision log.
import { describe, expect, it } from "vitest";
import { ACTIONS } from "./actions";
import { DB_ERROR_RULES, ErrorCode } from "./errors";
import { readRepoFile } from "./test-helpers";

const doc = readRepoFile("docs/api.md");
const model = readRepoFile("docs/domain-model.md") + readRepoFile("docs/decisions.md");

/** The text of each `### name` section in docs/api.md. */
function sections(): Map<string, string> {
  const map = new Map<string, string>();
  const parts = doc.split(/^### /m).slice(1);
  for (const part of parts) {
    const [heading = "", ...rest] = part.split("\n");
    // Action sections are headed by the bare action name; other ### headings are prose.
    if (/^[a-z][A-Za-z]+$/.test(heading.trim())) {
      map.set(heading.trim(), rest.join("\n").split(/^## /m)[0] ?? "");
    }
  }
  return map;
}

const GENERIC = ["UNAUTHENTICATED", "FORBIDDEN", "VALIDATION", "RATE_LIMITED", "INTERNAL"];

describe("docs/api.md matches the action registry", () => {
  const docSections = sections();

  it("documents every action, and only those", () => {
    expect([...docSections.keys()].sort()).toEqual(Object.keys(ACTIONS).sort());
  });

  for (const [name, action] of Object.entries(ACTIONS)) {
    it(`${name}: access and errors match`, () => {
      const text = docSections.get(name) ?? "";
      expect(text).toContain(`| Access | ${action.access} |`);
      const documented = new Set(
        [...text.matchAll(/`([A-Z_]+)`/g)].map((m) => m[1] ?? "").filter((c) => ErrorCode.options.includes(c as never)),
      );
      expect([...documented].sort()).toEqual([...action.errors].sort());
      for (const code of action.errors) expect(GENERIC).not.toContain(code);
    });
  }
});

describe("error codes", () => {
  it("every code can actually be returned by an action or a database rule", () => {
    const used = new Set<string>([
      ...GENERIC,
      "INTERNAL_INVARIANT",
      ...Object.values(ACTIONS).flatMap((a) => [...a.errors]),
      ...DB_ERROR_RULES.map((r) => r.code),
    ]);
    expect(ErrorCode.options.filter((c) => !used.has(c))).toEqual([]);
  });
});

describe("cited rules exist", () => {
  const cited = new Set(Object.values(ACTIONS).flatMap((a) => [...a.rules]));

  it.each([...cited].sort())("%s is defined", (rule) => {
    if (rule.startsWith("§")) {
      expect(model).toMatch(new RegExp(`^## ${rule.slice(1)}\\. `, "m"));
    } else {
      expect(model).toMatch(new RegExp(`\\b${rule}\\b`));
    }
  });
});
