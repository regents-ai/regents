import {execFileSync} from "node:child_process"
import {existsSync, readFileSync} from "node:fs"
import {test as base, expect} from "@playwright/test"

const port = process.env.PORT || "4002"

// The connections the test server holds open to anywhere but this machine, read
// from the process listening on the test port. A server-side read of a live
// site, a chain or any other outside address shows up here.
function serverOutsideConnections(): string[] {
  const run = (args: string[]) => {
    try {
      return execFileSync("lsof", args, {encoding: "utf8"})
    } catch {
      return ""
    }
  }
  const pid = run([`-tiTCP:${port}`, "-sTCP:LISTEN"]).trim().split("\n")[0]
  if (!pid) return []
  return run(["-nP", "-a", "-p", pid, "-iTCP", "-sTCP:ESTABLISHED"])
    .split("\n")
    .map(line => line.trim().split(/\s+/).at(-2) ?? "")
    .filter(name => name.includes("->"))
    .map(name => name.split("->")[1])
    .filter(remote => !/^(127\.0\.0\.1|\[::1\]|localhost):/.test(remote))
}

// The requests the test server refused to send outside this machine, from the
// log its Req adapter writes (Regents.OutsideRequests).
function serverRefusedRequests(): string[] {
  const log = process.env.REGENTS_OUTSIDE_LOG!
  return existsSync(log) ? readFileSync(log, "utf8").split("\n").filter(Boolean) : []
}

// A one-pixel GIF, for the Club Pass pictures the gallery shows from media.regents.sh.
const pixel = Buffer.from("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7", "base64")

// Every test's browser stays on this machine: the one outside service pages call,
// media.regents.sh's pictures, is answered with a pixel, and a request anywhere
// else is answered empty and recorded, and the test fails on it. The test also
// fails once the server has refused a request to an outside address, or if it
// held a connection outside when the test ended.
export const test = base.extend<{outside: string[]; serverOffline: void}>({
  outside: async ({context}, use) => {
    const outside: string[] = []
    await context.route(url => !["127.0.0.1", "localhost"].includes(url.hostname), route => {
      const url = new URL(route.request().url())
      if (url.hostname === "media.regents.sh")
        return route.fulfill({body: pixel, contentType: "image/gif"})
      outside.push(url.origin + url.pathname)
      return route.fulfill({status: 204})
    })
    await use(outside)
    expect(outside, "requests that left the test machine").toEqual([])
  },
  page: async ({page, outside: _outside}, use) => use(page),
  serverOffline: [
    async ({}, use) => {
      await use()
      expect(serverRefusedRequests(), "server requests to outside addresses").toEqual([])
      expect(serverOutsideConnections(), "server connections that left the test machine").toEqual([])
    },
    {auto: true},
  ],
})

export {expect}
export type {Locator, Page} from "@playwright/test"
