import { describe, expect, it } from "vitest";
import { DB_ENUMS } from "./common";
import { migrationsSql } from "./test-helpers";

// Every Postgres enum, as the migrations define it.
function dbEnums(): Map<string, string[]> {
  const found = new Map<string, string[]>();
  const re = /create type public\.([a-z_]+) as enum \(([^;]*)\);/g;
  for (const m of migrationsSql().matchAll(re)) {
    const labels = [...(m[2] ?? "").matchAll(/'([^']+)'/g)].map((l) => l[1] ?? "");
    found.set(m[1] ?? "", labels);
  }
  return found;
}

describe("enums match the database", () => {
  const db = dbEnums();

  it("finds the enums in the migrations", () => {
    expect(db.size).toBeGreaterThan(20);
  });

  it("covers every database enum, and nothing else", () => {
    expect(Object.keys(DB_ENUMS).sort()).toEqual([...db.keys()].sort());
  });

  for (const [name, schema] of Object.entries(DB_ENUMS)) {
    it(`${name} has the same values in the same order`, () => {
      expect([...schema.options]).toEqual(db.get(name));
    });
  }
});
