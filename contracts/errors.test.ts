import { describe, expect, it } from "vitest";
import { DB_ERROR_RULES, ErrorCode, mapDbError } from "./errors";
import { migrationsSql } from "./test-helpers";

const sql = migrationsSql();

/** Every message Anode's database functions raise, with % placeholders filled in. */
const raisedMessages = [...sql.matchAll(/raise exception '((?:[^']|'')*)'/g)].map((m) =>
  (m[1] ?? "").replaceAll("''", "'").replaceAll("%", "x1"),
);

/** Every named check constraint and unique index. */
const namedConstraints = [
  ...[...sql.matchAll(/constraint ([a-z0-9_]+) check/g)].map((m) => m[1] ?? ""),
  ...[...sql.matchAll(/create unique index ([a-z0-9_]+)/g)].map((m) => m[1] ?? ""),
];

describe("every database error is mapped", () => {
  it("finds the raised messages and constraints", () => {
    expect(raisedMessages.length).toBeGreaterThan(50);
    expect(namedConstraints.length).toBeGreaterThan(10);
  });

  it.each(raisedMessages)("raised message: %s", (message) => {
    const rule = DB_ERROR_RULES.find((r) => r.pattern?.test(message));
    expect(rule, `no rule matches "${message}"; add one to DB_ERROR_RULES`).toBeDefined();
  });

  it.each(namedConstraints)("constraint: %s", (name) => {
    expect(DB_ERROR_RULES.some((r) => r.constraint === name), `no rule for constraint ${name}`).toBe(true);
  });

  it("has no dead rules", () => {
    const dead = DB_ERROR_RULES.filter((r) =>
      r.constraint !== undefined
        ? !namedConstraints.includes(r.constraint)
        : !raisedMessages.some((m) => r.pattern?.test(m)),
    );
    expect(dead.map((r) => r.constraint ?? String(r.pattern))).toEqual([]);
  });

  it("uses only known error codes and never leaks SQL in messages", () => {
    for (const r of DB_ERROR_RULES) {
      expect(ErrorCode.options).toContain(r.code);
      expect(r.message).not.toMatch(/constraint|relation|violates|_/);
    }
  });
});

describe("mapDbError", () => {
  it("maps a named check constraint as Postgres reports it", () => {
    expect(
      mapDbError({
        code: "23514",
        message: 'new row for relation "photo" violates check constraint "photo_gradeable_needs_scale"',
      }).code,
    ).toBe("PHOTO_NEEDS_SCALE");
  });

  it("maps a unique index as Postgres reports it", () => {
    expect(
      mapDbError({ code: "23505", message: 'duplicate key value violates unique constraint "photo_one_gradeable"' }).code,
    ).toBe("PHOTO_ALREADY_GRADED");
  });

  it("maps a trigger message with values filled in", () => {
    expect(mapDbError({ code: "23514", message: "grade 6 is outside ISO 4628-3 (0 to 5)" }).code).toBe("GRADE_OUT_OF_RANGE");
    expect(mapDbError({ code: "23514", message: "the reviewer must be an inspector or admin of the organisation" }).code).toBe(
      "ROLE_INSUFFICIENT",
    );
  });

  it("maps row-level security refusals to FORBIDDEN", () => {
    expect(mapDbError({ code: "42501", message: 'new row violates row-level security policy for table "asset"' }).code).toBe(
      "FORBIDDEN",
    );
  });

  it("falls back by SQLSTATE, then to INTERNAL", () => {
    expect(mapDbError({ code: "23503", message: "insert or update violates foreign key" }).code).toBe("NOT_FOUND");
    expect(mapDbError({ code: "XX000", message: "boom" })).toEqual({
      code: "INTERNAL",
      message: "Something went wrong. Please try again.",
    });
  });
});
