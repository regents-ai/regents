import {generateKeyPairSync} from "node:crypto"
import {tmpdir} from "node:os"
import {join} from "node:path"
import {defineConfig, devices} from "@playwright/test"

const port = process.env.PORT || "4002"
const baseURL = `http://127.0.0.1:${port}`

// Where the test server writes every request it refused to send outside this
// machine. One file per run, named once here and inherited by the server and
// the workers, which fail any test that finds it written.
process.env.REGENTS_OUTSIDE_LOG ??= join(tmpdir(), `regents-outside-${port}-${Date.now()}.log`)

// The Privy key pair of this run: the test server checks Privy tokens with the
// public half, and test/browser/support/privy_service.ts signs them with the
// private half. Made once here and inherited by the server and the workers.
if (!process.env.REGENTS_BROWSER_PRIVY_KEY) {
  const {publicKey, privateKey} = generateKeyPairSync("ec", {
    namedCurve: "P-256",
    publicKeyEncoding: {type: "spki", format: "pem"},
    privateKeyEncoding: {type: "pkcs8", format: "pem"},
  })
  process.env.REGENTS_BROWSER_PRIVY_KEY = publicKey
  process.env.REGENTS_BROWSER_PRIVY_SIGNING_KEY = privateKey
}

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
