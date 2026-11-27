import assert from "node:assert/strict"
import {readFileSync} from "node:fs"
import {test} from "node:test"
import {
  PRODUCT_TOOLS,
  buildAnnotations,
  buildSchema,
  manifestPathBuilder,
  runSpec,
} from "./product_webmcp.ts"

const keyfleetManifest = JSON.parse(
  readFileSync(new URL("../../priv/keyfleet/tool_manifest.json", import.meta.url), "utf8"),
)
const manifestByName = new Map(keyfleetManifest.tools.map(tool => [tool.name, tool]))

function keyfleetSpec(name) {
  const spec = PRODUCT_TOOLS.keyfleet.find(item => item.name === name)
  assert.ok(spec, `Expected Keyfleet WebMCP spec ${name}`)
  return spec
}

test("keyfleet_workspace_pulse forwards after cursor and polls empty when unchanged", async () => {
  const spec = keyfleetSpec("keyfleet_workspace_pulse")
  const requestedUrls = []

  const fakeFetch = async url => {
    requestedUrls.push(String(url))
    const parsed = new URL(String(url), "https://regents.sh")
    const after = parsed.searchParams.get("after")

    const payload =
      after === "9488"
        ? {
            fleet_id: "fleet_tech_classic",
            activity: [],
            next_after: "9488",
            has_more: false,
            notebooks_configured: true,
          }
        : {
            fleet_id: "fleet_tech_classic",
            activity: [
              {
                seq: 9488,
                key: 9,
                agent_name: "Pira",
                project_title: "marimo lab",
                text: "Agent Pira with Key 9 worked on marimo lab",
              },
            ],
            next_after: "9488",
            has_more: false,
            notebooks_configured: true,
          }

    return new Response(JSON.stringify(payload), {
      status: 200,
      headers: {"content-type": "application/json"},
    })
  }

  const controller = new AbortController()

  const first = await runSpec(spec, {fleet_id: "fleet_tech_classic"}, controller.signal, fakeFetch)
  assert.equal(first.ok, true)
  assert.equal(first.body.activity.length, 1)
  assert.equal(first.body.next_after, "9488")

  const second = await runSpec(
    spec,
    {fleet_id: "fleet_tech_classic", after: first.body.next_after},
    controller.signal,
    fakeFetch,
  )
  assert.equal(second.ok, true)
  assert.deepEqual(second.body.activity, [])
  assert.equal(second.body.next_after, "9488")
  assert.equal(second.body.has_more, false)

  assert.deepEqual(requestedUrls, [
    "/api/v1/keyfleet/fleets/fleet_tech_classic/workspace/pulse",
    "/api/v1/keyfleet/fleets/fleet_tech_classic/workspace/pulse?after=9488",
  ])
})

test("manifestPathBuilder omits blank, null, and undefined cursors", () => {
  const pulsePath = manifestPathBuilder("/api/v1/keyfleet/fleets/{fleet_id}/workspace/pulse")
  assert.equal(
    pulsePath({fleet_id: "fleet_tech_classic", after: ""}),
    "/api/v1/keyfleet/fleets/fleet_tech_classic/workspace/pulse",
  )
  assert.equal(
    pulsePath({fleet_id: "fleet_tech_classic", after: "   "}),
    "/api/v1/keyfleet/fleets/fleet_tech_classic/workspace/pulse",
  )
  assert.equal(
    pulsePath({fleet_id: "fleet_tech_classic", after: null}),
    "/api/v1/keyfleet/fleets/fleet_tech_classic/workspace/pulse",
  )
  assert.equal(
    pulsePath({fleet_id: "fleet_tech_classic", after: undefined}),
    "/api/v1/keyfleet/fleets/fleet_tech_classic/workspace/pulse",
  )
  assert.equal(
    pulsePath({fleet_id: "fleet_tech_classic", after: "9488"}),
    "/api/v1/keyfleet/fleets/fleet_tech_classic/workspace/pulse?after=9488",
  )
})

test("proposals and seasons forward before cursors", () => {
  const proposals = keyfleetSpec("keyfleet_fleet_proposals")
  const seasons = keyfleetSpec("keyfleet_fleet_seasons")

  assert.equal(
    proposals.path({fleet_id: "fleet_tech_classic", before: "12"}),
    "/api/v1/keyfleet/fleets/fleet_tech_classic/proposals?before=12",
  )
  assert.equal(
    seasons.path({fleet_id: "fleet_tech_classic", before: "4"}),
    "/api/v1/keyfleet/fleets/fleet_tech_classic/seasons?before=4",
  )
})

test("buildSchema and buildAnnotations align workspace_pulse with canonical manifest", () => {
  const pulseSpec = keyfleetSpec("keyfleet_workspace_pulse")
  const pulseEntry = manifestByName.get("workspace_pulse")
  assert.ok(pulseEntry)

  const hydratedSchema = buildSchema(pulseSpec, pulseEntry)
  assert.ok(hydratedSchema.properties.fleet_id)
  assert.ok(hydratedSchema.properties.after)
  assert.deepEqual(hydratedSchema.required, ["fleet_id"])

  const offlineSchema = buildSchema(pulseSpec, undefined)
  assert.ok(offlineSchema.properties.fleet_id)
  assert.ok(offlineSchema.properties.after)

  const hydratedAnn = buildAnnotations("keyfleet", pulseSpec, pulseEntry)
  assert.equal(hydratedAnn.readOnlyHint, true)
  assert.equal(hydratedAnn.untrustedContentHint, true)

  const offlineAnn = buildAnnotations("keyfleet", pulseSpec, undefined)
  assert.equal(offlineAnn.untrustedContentHint, true)

  assert.doesNotMatch(pulseEntry.description, /without notes, titles or authors/i)
  assert.match(pulseEntry.description, /agent name/i)
  assert.match(pulseEntry.description, /project title/i)
})
