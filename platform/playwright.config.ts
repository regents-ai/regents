import {defineConfig, devices} from "@playwright/test"

const baseURL = `http://127.0.0.1:${process.env.PORT || "4002"}`

export default defineConfig({
  testDir: "./test/browser",
  fullyParallel: false,
  workers: 1,
  forbidOnly: true,
  retries: 0,
  reporter: "line",
  use: {
    baseURL,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  webServer: {
    // Its own database, so what this server saves never reaches `mix test`.
    command:
      "export MIX_ENV=test MIX_TEST_PARTITION=${MIX_TEST_PARTITION}_browser REGENTS_BROWSER_TEST=1 && mix do ecto.create --quiet + regents.setup_local_auth + run -e 'Regents.BrowserStakingReading.warm!()' + phx.server",
    url: `${baseURL}/`,
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
