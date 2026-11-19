// model/schemas/*.json must match the Zod contract (run npm run schemas after changing it).
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { measureSchemas } from "./measure-schemas";

describe("measurement-model JSON Schemas are current", () => {
  for (const [name, schema] of Object.entries(measureSchemas())) {
    it(name, () => {
      expect(JSON.parse(readFileSync(join(__dirname, "..", "model", "schemas", name), "utf8"))).toEqual(schema);
    });
  }
});
