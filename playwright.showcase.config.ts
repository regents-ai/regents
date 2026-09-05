import {defineConfig, devices} from "@playwright/test"

// Use an already-running isolated worktree server. No product seeding or teardown.
export default defineConfig({
  testDir: "./test/browser",
  testMatch: "showcase.spec.ts",
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: "line",
  use: {
    baseURL: `http://127.0.0.1:${process.env.PORT || "4002"}`,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [{name: "chromium", use: {...devices["Desktop Chrome"]}}],
})
