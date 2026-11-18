import {availableParallelism, tmpdir} from "node:os"
import {join} from "node:path"
import {defineConfig, devices} from "@playwright/test"

// One browser for every three of the machine's cores, at most five: the Mac runs three
// checks at once, and each walk's server, its database and the check's other gates need
// cores too. Every browser reaches that one server, its one database and the state
// prepared before it starts, so a file whose tests change something its own other
// tests read keeps them in order (`test.describe.configure`), and a test that changes
// what other files read signs in as its own person.
const workers = Math.max(1, Math.min(5, Math.floor(availableParallelism() / 3)))
const port = process.env.PORT || "4002"
const baseURL = `http://127.0.0.1:${port}`

// Where the test server writes every request it refused to send outside this
// machine. One file per run, named once here and inherited by the server and
// the workers, which fail any test that finds it written.
process.env.REGENTS_OUTSIDE_LOG ??= join(tmpdir(), `regents-outside-${port}-${Date.now()}.log`)

export default defineConfig({
  testDir: "./test/browser",
  fullyParallel: true,
  workers,
  forbidOnly: true,
  retries: 0,
  reporter: "line",
  use: {
    baseURL,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    // Every walk starts with the Stake page's guided tour seen, so it never opens
    // over what a walk presses. A walk signs in inside its own browser, which keeps
    // the tour seen; tour.spec.ts starts with nothing kept.
    storageState: {
      cookies: [],
      origins: [{origin: baseURL, localStorage: [{name: "regent:tour:stake", value: "seen"}]}],
    },
  },
  webServer: {
    // Its own database, so what this server saves never reaches `mix test`.
    command:
      "mkdir -p tmp && rm -f tmp/walk-lines.jsonl && " +
      "export MIX_ENV=test MIX_TEST_PARTITION=${MIX_TEST_PARTITION}_browser REGENTS_BROWSER_TEST=1 && mix do ecto.create --quiet + regents.setup_local_auth + run -e 'Regents.BrowserStakingReading.warm!(); Regents.BrowserAgents.pair!()' + phx.server",
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
