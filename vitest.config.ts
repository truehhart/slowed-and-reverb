import { defineConfig } from "vitest/config";

// Pure-logic unit tests only (src/ui-math.ts). No DOM, so the default node
// environment is fine; Playwright covers anything that touches the page.
export default defineConfig({
  test: {
    include: ["tests/unit/**/*.test.ts"],
  },
});
