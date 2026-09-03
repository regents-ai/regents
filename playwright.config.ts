import {defineConfig, devices} from "@playwright/test"

export default defineConfig({
  testDir: "./test/browser",
  globalTeardown: "./test/browser/support/autolaunch_subject_teardown.ts",
  fullyParallel: false,
  workers: 1,
  forbidOnly: true,
  retries: 0,
  reporter: "line",
  use: {
    baseURL: "http://127.0.0.1:4002",
    trace: "retain-on-failure",
  },
  webServer: {
    command:
      "MIX_ENV=test mix ash_platform.seed_browser_autolaunch_draft_owner && MIX_ENV=test mix ash_platform.seed_browser_autolaunch_subject && MIX_ENV=test ASH_PLATFORM_BROWSER_TEST=1 mix phx.server",
    url: "http://127.0.0.1:4002/",
    reuseExistingServer: false,
    timeout: 120_000,
  },
  projects: [
    {
      name: "chromium",
      use: {...devices["Desktop Chrome"]},
    },
  ],
})
