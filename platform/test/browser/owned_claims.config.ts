import {defineConfig, devices} from "@playwright/test"

// Browser-only component fixture; transport and Ash authorization have separate tests.
export default defineConfig({
  testDir: ".", testMatch: "owned_claims.spec.ts", workers: 1, retries: 0,
  outputDir: "../../test-results/owned-claims", reporter: "line",
  use: {...devices["Desktop Chrome"], trace: "retain-on-failure", screenshot: "only-on-failure"},
})
