// Writes model/schemas/*.json from the Stage 3 contract (contracts/findings.ts).
//   npm run schemas
import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { measureSchemas } from "../contracts/measure-schemas";

for (const [name, schema] of Object.entries(measureSchemas())) {
  writeFileSync(join(__dirname, "..", "model", "schemas", name), JSON.stringify(schema, null, 2) + "\n");
  console.log(`wrote model/schemas/${name}`);
}
