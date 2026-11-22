// Product-specific WebMCP read tools (document.modelContext) for the folded
// Techtree, Keyfleet, Autolaunch, and Patchbay routes on one-site.
// Registers the active product's public read tools alongside Regents' site-wide
// tools (public_tools.ts) with clean pageshow/pagehide lifecycle management.
import {visitId} from "./visit_log"

type Schema = {
  type: "object"
  properties: Record<string, {type: string; description?: string}>
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
  title: string
  description: string
  properties?: Record<string, {type: string; description?: string}>
  required?: string[]
  accept?: "application/json" | "text/markdown"
  path: (input: Record<string, string>) => string
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
      title: "List Keyfleet fleets",
      description: "List all Keyfleet fleets and their status.",
      path: () => "/api/v1/keyfleet/fleets",
    },
    {
      name: "keyfleet_fleet_show",
      title: "Read one Keyfleet fleet",
      description: "Read one Keyfleet fleet directory record by fleet_id (e.g. fleet_tech_classic).",
      properties: {fleet_id: {type: "string", description: "Fleet id"}},
      required: ["fleet_id"],
      path: input => `/api/v1/keyfleet/fleets/${encodeURIComponent(input.fleet_id)}`,
    },
    {
      name: "keyfleet_fleet_proposals",
      title: "List Keyfleet proposals",
      description: "Read public governance proposals for a Keyfleet fleet.",
      properties: {fleet_id: {type: "string", description: "Fleet id"}},
      required: ["fleet_id"],
      path: input => `/api/v1/keyfleet/fleets/${encodeURIComponent(input.fleet_id)}/proposals`,
    },
    {
      name: "keyfleet_fleet_treasury",
      title: "Read Keyfleet treasury",
      description: "Read public treasury balance and history for a Keyfleet fleet.",
      properties: {fleet_id: {type: "string", description: "Fleet id"}},
      required: ["fleet_id"],
      path: input => `/api/v1/keyfleet/fleets/${encodeURIComponent(input.fleet_id)}/treasury`,
    },
    {
      name: "keyfleet_fleet_seasons",
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
      title: "Search Patchbay threads",
      description: "Search Patchbay forum questions and verified fixes by query text.",
      properties: {q: {type: "string", description: "Search query text"}},
      required: ["q"],
      path: input => `/api/v1/patchbay/forum/search?${new URLSearchParams({q: input.q})}`,
    },
    {
      name: "patchbay_get_thread",
      title: "Read one Patchbay thread",
      description: "Read one Patchbay forum thread and its replies by ID.",
      properties: {id: {type: "string", description: "Thread ID"}},
      required: ["id"],
      path: input => `/api/v1/patchbay/forum/threads/${encodeURIComponent(input.id)}`,
    },
    {
      name: "patchbay_help",
      title: "Read Patchbay agent help",
      description: "Read Patchbay's structured help guide for agents.",
      path: () => "/api/v1/patchbay/forum/help",
    },
    {
      name: "patchbay_capabilities",
      title: "Read Patchbay capabilities",
      description: "Read Patchbay's WebMCP and forum capabilities manifest.",
      path: () => "/api/v1/patchbay/forum/capabilities",
    },
    {
      name: "patchbay_wallet_bench",
      title: "Read Agent Wallet Bench",
      description: "Read the live Agent Wallet Bench results matrix as JSON.",
      path: () => "/api/v1/patchbay/wallet-bench",
    },
    {
      name: "patchbay_sites_markdown",
      title: "List Patchbay sites",
      description: "Read the Patchbay WebMCP site directory as Markdown.",
      accept: "text/markdown",
      path: () => "/patchbay/sites",
    },
  ],
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
    const body = accept === "text/markdown" ? await response.text() : await response.json()
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
  const specs = PRODUCT_TOOLS[product]
  const context = (documentRoot as Document & {modelContext: ModelContext}).modelContext
  let group: AbortController | undefined

  const start = () => {
    if (group) return
    const current = new AbortController()
    group = current
    const annotations = product === "patchbay" ? UNTRUSTED_READ_ANNOTATIONS : READ_ANNOTATIONS
    void Promise.all(
      specs.map(spec => {
        const schema: Schema = {
          type: "object",
          properties: spec.properties ?? {},
          required: spec.required ?? [],
          additionalProperties: false,
        }
        const tool: Tool = {
          name: spec.name,
          title: spec.title,
          description: spec.description,
          inputSchema: schema,
          annotations,
          execute: input => runSpec(spec, input, current.signal),
        }
        return Promise.resolve().then(() => context.registerTool(tool, {signal: current.signal}))
      }),
    )
  }

  window.addEventListener("pagehide", () => {
    group?.abort()
    group = undefined
  })
  window.addEventListener("pageshow", start)
  start()
}
