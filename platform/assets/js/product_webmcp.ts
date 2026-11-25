// Product-specific WebMCP read tools (document.modelContext) for the folded
// Techtree, Keyfleet, Autolaunch, and Patchbay routes on one-site.
// Hydrates titles, descriptions, schemas, and annotations directly from each
// product's canonical `priv/<product>/tool_manifest.json` via
// `GET /api/v1/<product>/capabilities`, with a safe built-in route table so
// public GET tools never drift from the canonical manifest.
import {visitId} from "./visit_log"

type Schema = {
  type: "object"
  properties: Record<string, {type?: string; description?: string; enum?: string[]}>
  required: string[]
  additionalProperties: false
}

type Annotations = {
  readOnlyHint: boolean
  untrustedContentHint: boolean
  consequentialHint: boolean
}

type Tool = {
  name: string
  title: string
  description: string
  inputSchema: Schema
  annotations: Annotations
  execute(input: unknown, client?: unknown): Promise<unknown>
}

type ModelContext = {
  registerTool(tool: Tool, options: {signal: AbortSignal}): Promise<void> | void
}

type ToolSpec = {
  name: string
  manifestName?: string
  title: string
  description: string
  properties?: Record<string, {type?: string; description?: string}>
  required?: string[]
  accept?: "application/json" | "text/markdown"
  path: (input: Record<string, string>) => string
}

type ManifestHttp = {
  method?: string
  path?: string
  accept?: "application/json" | "text/markdown"
}

type ManifestTool = {
  name?: string
  title?: string
  description?: string
  requires?: string
  authentication?: string
  effect?: string
  input_schema?: {
    type?: string
    properties?: Record<string, {type?: string; description?: string; enum?: string[]}>
    required?: string[]
  }
  annotations?: Partial<Annotations>
  http?: ManifestHttp
}

const READ_ANNOTATIONS: Annotations = {
  readOnlyHint: true,
  untrustedContentHint: false,
  consequentialHint: false,
}

const UNTRUSTED_READ_ANNOTATIONS: Annotations = {
  readOnlyHint: true,
  untrustedContentHint: true,
  consequentialHint: false,
}

const PRODUCT_TOOLS: Record<string, ToolSpec[]> = {
  techtree: [
    {
      name: "techtree_catalog",
      title: "Read Techtree catalog",
      description: "Read the active Techtree catalog of Climbs and Skills.",
      path: () => "/api/v1/techtree/catalog",
    },
    {
      name: "techtree_bootstrap",
      title: "Read Techtree bootstrap",
      description: "Read Techtree CLI bootstrap and install metadata.",
      path: () => "/api/v1/techtree/bootstrap",
    },
    {
      name: "techtree_publications",
      title: "List Techtree results",
      description: "List published Techtree evaluation results.",
      path: () => "/api/v1/techtree/publications",
    },
    {
      name: "techtree_climb",
      title: "Read a Techtree Climb",
      description: "Read the fixed task contract for one Techtree Climb by slug.",
      properties: {slug: {type: "string", description: "Climb slug"}},
      required: ["slug"],
      path: input => `/api/v1/techtree/climbs/${encodeURIComponent(input.slug)}`,
    },
    {
      name: "techtree_docs_markdown",
      title: "Read Techtree Docs",
      description: "Read Techtree's docs index as Markdown.",
      accept: "text/markdown",
      path: () => "/techtree/docs",
    },
  ],
  keyfleet: [
    {
      name: "keyfleet_fleets_list",
      manifestName: "fleets_list",
      title: "List Keyfleet fleets",
      description: "List all Keyfleet fleets and their status.",
      path: () => "/api/v1/keyfleet/fleets",
    },
    {
      name: "keyfleet_fleet_show",
      manifestName: "fleets_show",
      title: "Read one Keyfleet fleet",
      description: "Read one Keyfleet fleet directory record by fleet_id (e.g. fleet_tech_classic).",
      properties: {fleet_id: {type: "string", description: "Fleet id"}},
      required: ["fleet_id"],
      path: input => `/api/v1/keyfleet/fleets/${encodeURIComponent(input.fleet_id)}`,
    },
    {
      name: "keyfleet_fleet_proposals",
      manifestName: "proposals_list",
      title: "List Keyfleet proposals",
      description: "Read public governance proposals for a Keyfleet fleet.",
      properties: {fleet_id: {type: "string", description: "Fleet id"}},
      required: ["fleet_id"],
      path: input => `/api/v1/keyfleet/fleets/${encodeURIComponent(input.fleet_id)}/proposals`,
    },
    {
      name: "keyfleet_fleet_treasury",
      manifestName: "treasury_show",
      title: "Read Keyfleet treasury",
      description: "Read public treasury balance and history for a Keyfleet fleet.",
      properties: {fleet_id: {type: "string", description: "Fleet id"}},
      required: ["fleet_id"],
      path: input => `/api/v1/keyfleet/fleets/${encodeURIComponent(input.fleet_id)}/treasury`,
    },
    {
      name: "keyfleet_fleet_seasons",
      manifestName: "seasons_list",
      title: "List Keyfleet seasons",
      description: "Read public trading seasons for a Keyfleet fleet.",
      properties: {fleet_id: {type: "string", description: "Fleet id"}},
      required: ["fleet_id"],
      path: input => `/api/v1/keyfleet/fleets/${encodeURIComponent(input.fleet_id)}/seasons`,
    },
  ],
  autolaunch: [
    {
      name: "autolaunch_auctions",
      title: "List Autolaunch auctions",
      description: "List public Revstake and Memestock auctions on Autolaunch.",
      path: () => "/api/v1/autolaunch/auctions",
    },
    {
      name: "autolaunch_auction_counts",
      title: "Read Autolaunch auction counts",
      description: "Read counts of live, upcoming, and graduated Autolaunch auctions.",
      path: () => "/api/v1/autolaunch/auction-counts",
    },
    {
      name: "autolaunch_tokens",
      title: "List Autolaunch tokens",
      description: "List tokens launched through Autolaunch on Base and Robinhood Chain.",
      path: () => "/api/v1/autolaunch/tokens",
    },
    {
      name: "autolaunch_earn_products",
      title: "List Autolaunch Earn products",
      description: "Read available USDC lending products on Autolaunch Earn.",
      path: () => "/api/v1/autolaunch/earn/products",
    },
  ],
  patchbay: [
    {
      name: "patchbay_search_threads",
      manifestName: "search_threads",
      title: "Search Patchbay threads",
      description: "Search Patchbay forum questions and verified fixes by query text.",
      properties: {q: {type: "string", description: "Search query text"}},
      required: ["q"],
      path: input => `/api/v1/patchbay/forum/search?${new URLSearchParams({q: input.q})}`,
    },
    {
      name: "patchbay_get_thread",
      manifestName: "get_thread",
      title: "Read one Patchbay thread",
      description: "Read one Patchbay forum thread and its replies by ID.",
      properties: {id: {type: "string", description: "Thread ID"}},
      required: ["id"],
      path: input => `/api/v1/patchbay/forum/threads/${encodeURIComponent(input.id)}`,
    },
    {
      name: "patchbay_help",
      manifestName: "get_help",
      title: "Read Patchbay agent help",
      description: "Read Patchbay's structured help guide for agents.",
      path: () => "/api/v1/patchbay/forum/help",
    },
    {
      name: "patchbay_capabilities",
      manifestName: "capabilities",
      title: "Read Patchbay capabilities",
      description: "Read Patchbay's WebMCP and forum capabilities manifest.",
      path: () => "/api/v1/patchbay/capabilities",
    },
    {
      name: "patchbay_wallet_bench",
      manifestName: "wallet_bench",
      title: "Read Agent Wallet Bench",
      description: "Read the live Agent Wallet Bench results matrix as JSON.",
      path: () => "/api/v1/patchbay/wallet-bench",
    },
    {
      name: "patchbay_sites_markdown",
      manifestName: "list_sites",
      title: "List Patchbay sites",
      description: "Read the Patchbay WebMCP site directory as Markdown.",
      accept: "text/markdown",
      path: () => "/patchbay/sites",
    },
    {
      name: "patchbay_offers",
      manifestName: "list_offers",
      title: "List Patchbay agent offers",
      description: "Read active Patchbay Agent Offers placements, slots, and current leases as JSON.",
      path: () => "/api/v1/patchbay/offers",
    },
    {
      name: "patchbay_services",
      title: "List Patchbay commerce services",
      description:
        "Browse Patchbay's indexed x402, MPP (Tempo), MCP, and WebMCP agentic commerce services.",
      properties: {
        q: {type: "string", description: "Optional search query"},
        protocol: {type: "string", description: "Optional protocol filter (x402, mpp, mcp, webmcp)"},
      },
      path: input => {
        const params = new URLSearchParams()
        if (input.q) params.set("q", input.q)
        if (input.protocol) params.set("protocol", input.protocol)
        const qs = params.toString()
        return qs ? `/api/v1/patchbay/services?${qs}` : "/api/v1/patchbay/services"
      },
    },
    {
      name: "patchbay_critical_cves",
      title: "List active critical CVEs",
      description: "Read active critical and CISA KEV vulnerabilities mirrored from cve.now.",
      path: () => "/api/v1/patchbay/security/criticals",
    },
    {
      name: "patchbay_playbooks",
      title: "List Patchbay playbooks",
      description: "List agent support playbooks for x402, MPP (Tempo), and active CVE triage.",
      path: () => "/api/v1/patchbay/playbooks",
    },
    {
      name: "patchbay_known_fixes",
      title: "List Patchbay known fixes",
      description: "Read verified remediation notes for x402, MPP, SIWA, MCP, and WebMCP failures.",
      path: () => "/api/v1/patchbay/known-fixes",
    },
  ],
}

async function fetchManifestTools(
  product: string,
  signal: AbortSignal,
): Promise<Map<string, ManifestTool>> {
  const byName = new Map<string, ManifestTool>()
  try {
    const response = await fetch(`/api/v1/${encodeURIComponent(product)}/capabilities`, {
      headers: {Accept: "application/json"},
      credentials: "omit",
      signal,
    })
    if (!response.ok) return byName
    const payload = (await response.json()) as {tools?: unknown}
    if (!Array.isArray(payload.tools)) return byName
    for (const raw of payload.tools) {
      if (raw && typeof raw === "object" && typeof (raw as ManifestTool).name === "string") {
        const entry = raw as ManifestTool
        byName.set(entry.name as string, entry)
      }
    }
  } catch {
    // Offline or aborted: fall back cleanly to built-in route descriptors.
  }
  return byName
}

function buildAnnotations(product: string, entry?: ManifestTool): Annotations {
  const defaults = product === "patchbay" ? UNTRUSTED_READ_ANNOTATIONS : READ_ANNOTATIONS
  const ann = entry?.annotations
  if (!ann) return defaults
  return {
    readOnlyHint: typeof ann.readOnlyHint === "boolean" ? ann.readOnlyHint : defaults.readOnlyHint,
    untrustedContentHint:
      typeof ann.untrustedContentHint === "boolean"
        ? ann.untrustedContentHint
        : defaults.untrustedContentHint,
    consequentialHint:
      typeof ann.consequentialHint === "boolean"
        ? ann.consequentialHint
        : defaults.consequentialHint,
  }
}

function buildSchema(spec: ToolSpec, entry?: ManifestTool): Schema {
  const props = spec.properties ?? entry?.input_schema?.properties ?? {}
  const required = spec.required ?? entry?.input_schema?.required ?? []
  return {
    type: "object",
    properties: props,
    required,
    additionalProperties: false,
  }
}

function manifestPathBuilder(template: string): (input: Record<string, string>) => string {
  return input => {
    const routeKeys = new Set<string>()
    const path = template.replace(/\{([a-zA-Z0-9_]+)\}/g, (_match, key: string) => {
      routeKeys.add(key)
      return encodeURIComponent(input[key] ?? "")
    })
    const query = new URLSearchParams()
    for (const [key, value] of Object.entries(input)) {
      if (routeKeys.has(key)) continue
      if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
        query.set(key, String(value))
      }
    }
    return query.size > 0 ? `${path}?${query}` : path
  }
}

function extraManifestSpecs(
  product: string,
  manifestTools: Map<string, ManifestTool>,
  registered: Set<string>,
): ToolSpec[] {
  const extras: ToolSpec[] = []
  for (const [name, entry] of manifestTools.entries()) {
    if (registered.has(name)) continue
    const http = entry.http
    if (!http || http.method !== "GET" || typeof http.path !== "string") continue
    if (!http.path.startsWith("/") || http.path.startsWith("//")) continue
    if (entry.requires && entry.requires !== "none") continue
    if (entry.authentication && entry.authentication !== "public") continue
    const toolName = name.startsWith(`${product}_`) ? name : `${product}_${name}`
    if (registered.has(toolName)) continue
    registered.add(toolName)
    extras.push({
      name: toolName,
      manifestName: name,
      title: entry.title ?? toolName,
      description: entry.description ?? "",
      properties: entry.input_schema?.properties,
      required: entry.input_schema?.required,
      accept: http.accept,
      path: manifestPathBuilder(http.path),
    })
  }
  return extras
}

async function runSpec(spec: ToolSpec, rawInput: unknown, signal: AbortSignal): Promise<unknown> {
  const input =
    rawInput && typeof rawInput === "object" && !Array.isArray(rawInput)
      ? (rawInput as Record<string, string>)
      : {}
  for (const key of spec.required ?? []) {
    if (typeof input[key] !== "string" || input[key].trim() === "") {
      return {ok: false, error: {code: "invalid_input", message: `Missing required string: ${key}`}}
    }
  }
  const accept = spec.accept ?? "application/json"
  const visit = visitId()
  try {
    const response = await fetch(spec.path(input), {
      headers: {Accept: accept, ...(visit && {"x-regent-visit": visit})},
      credentials: "omit",
      cache: "no-store",
      signal,
    })
    const contentType = response.headers.get("content-type") ?? ""
    const body = /(?:\/|\+)json(?:;|$)/i.test(contentType)
      ? await response.json()
      : await response.text()
    return {ok: response.ok, status: response.status, body}
  } catch {
    return {
      ok: false,
      error: {
        code: signal.aborted ? "aborted" : "network_error",
        message: signal.aborted ? "Request cancelled." : "Could not reach this site.",
      },
    }
  }
}

export function installProductWebMcpTools(documentRoot: Document = document): void {
  if (!("modelContext" in documentRoot)) return
  const product = documentRoot.documentElement.dataset.product
  if (!product || !(product in PRODUCT_TOOLS)) return
  const baseSpecs = PRODUCT_TOOLS[product]
  const context = (documentRoot as Document & {modelContext: ModelContext}).modelContext
  let group: AbortController | undefined

  const start = () => {
    if (group) return
    const current = new AbortController()
    group = current

    void (async () => {
      const manifestTools = await fetchManifestTools(product, current.signal)
      if (current.signal.aborted) return

      const seen = new Set<string>()
      for (const spec of baseSpecs) {
        seen.add(spec.name)
        if (spec.manifestName) seen.add(spec.manifestName)
      }
      const allSpecs = [...baseSpecs, ...extraManifestSpecs(product, manifestTools, seen)]

      await Promise.all(
        allSpecs.map(spec => {
          const entry =
            manifestTools.get(spec.name) ??
            (spec.manifestName ? manifestTools.get(spec.manifestName) : undefined)
          const tool: Tool = {
            name: spec.name,
            title: entry?.title ?? spec.title,
            description: entry?.description ?? spec.description,
            inputSchema: buildSchema(spec, entry),
            annotations: buildAnnotations(product, entry),
            execute: input => runSpec(spec, input, current.signal),
          }
          return Promise.resolve().then(() => context.registerTool(tool, {signal: current.signal}))
        }),
      )
    })()
  }

  window.addEventListener("pagehide", () => {
    group?.abort()
    group = undefined
  })
  window.addEventListener("pageshow", start)
  start()
}
