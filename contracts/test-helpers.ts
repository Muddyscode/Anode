// Helpers for tests that read the repository's migrations and docs.
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");

export function readRepoFile(path: string): string {
  return readFileSync(join(ROOT, path), "utf8");
}

/** All migration SQL, in order. */
export function migrationsSql(): string {
  const dir = join(ROOT, "supabase", "migrations");
  return readdirSync(dir)
    .filter((f) => f.endsWith(".sql"))
    .sort()
    .map((f) => readFileSync(join(dir, f), "utf8"))
    .join("\n");
}
