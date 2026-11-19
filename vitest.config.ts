import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

export default defineConfig({
  esbuild: { jsx: "automatic" },
  resolve: { alias: { "@": fileURLToPath(new URL(".", import.meta.url)) } },
  test: {
    include: ["contracts/**/*.test.ts", "design/**/*.test.ts", "components/**/*.test.tsx", "lib/**/*.test.ts"],
    coverage: {
      provider: "v8",
      // Stage 5 definition of done: 100% branch coverage on the grading engine.
      include: ["lib/grading/**/*.ts"],
      exclude: ["lib/grading/**/*.test.ts", "lib/grading/index.ts", "lib/grading/types.ts"],
      thresholds: { branches: 100, functions: 100, lines: 100, statements: 100 },
      reporter: ["text"],
    },
  },
});
