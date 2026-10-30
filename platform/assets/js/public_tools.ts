// WebMCP (document.modelContext): the read tools every regents.sh page offers.
// Every tool is described once, in priv/tool_manifest.json; this file adds only
// the request each one makes. None of them opens a wallet. A signed tool takes only
// its input; the agent's browser host signs the exact request (window.regentsSign),
// so no key, signature or receipt passes through the page.
import manifest from "../../priv/tool_manifest.json" with {type: "json"}
import {Refused, signedTools, type SignedOperation} from "../vendor/regent_agent_access/signed_tools"
import {report, visitId} from "./visit_log"

type Json = null | boolean | number | string | Json[] | {[key: string]: Json}
type Input = Record<string, string>
type Property = {type: string; enum?: string[]; description?: string}
type Schema = {
  type: "object"
  properties: Record<string, Property>
  required: string[]
  additionalProperties: false
}
type Annotations = {readOnlyHint: boolean; untrustedContentHint: boolean; consequentialHint: boolean}
type Entry = {
  name: string
  title: string
  description: string
  input_schema: Schema
  annotations: Annotations
  requires: "none" | "siwa" | "siwa_and_pairing"
  authentication: string
}
type Failure = {
  ok: false
  error: {
    code: "invalid_input" | "aborted" | "network_error" | "invalid_response"
    message: string
  }
}

type Tool = {
  name: string
  title: string
  description: string
  inputSchema: Schema
  annotations: Annotations
  execute(input: unknown, client?: unknown): Promise<unknown>
}
type ModelContext = {registerTool(tool: Tool, options: {signal: AbortSignal}): Promise<void> | void}
type Request = {path: string; accept: "application/json" | "text/markdown"}

const json = "application/json"
// The pages regents_about reads, by the manifest's page names.
const pages: Record<string, string> = {
  about: "/about",
  docs: "/docs",
  start: "/start",
  contact: "/contact",
  refunds: "/credits/refunds",
  privacy: "/privacy",
  terms: "/terms",
  cloak: "/cloak/guide",
}
const requests: Record<string, (input: Input) => Request> = {
  regents_about: input => ({path: pages[input.page], accept: "text/markdown"}),
  regents_products: () => ({path: "/api/v1/products", accept: json}),
  regents_product: input => ({path: `/api/v1/products/${encodeURIComponent(input.slug)}`, accept: json}),
  list_regents_webmcp_tools: () => ({path: "/api/v1/site-tools/regents", accept: json}),
  list_patchbay_webmcp_tools: () => ({path: "/api/v1/site-tools/patchbay", accept: json}),
  list_techtree_webmcp_tools: () => ({path: "/api/v1/site-tools/techtree", accept: json}),
  list_autolaunch_webmcp_tools: () => ({path: "/api/v1/site-tools/autolaunch", accept: json}),
  list_keyfleet_webmcp_tools: () => ({path: "/api/v1/site-tools/keyfleet", accept: json}),
  list_all_webmcp_tools: () => ({path: "/api/v1/site-tools", accept: json}),
  get_siwa_connection_help: () => ({path: "/api/v1/site-tools/siwa", accept: json}),
  regents_public_profile: input => ({path: `/api/v1/regents/${encodeURIComponent(input.slug)}`, accept: json}),
  regents_research_list: input => ({path: readingList("papers", input), accept: json}),
  regents_research_paper: input => ({path: `/api/v1/reading/papers/${encodeURIComponent(input.id)}`, accept: json}),
  regents_articles_list: input => ({path: readingList("articles", input), accept: json}),
  regents_article: input => ({path: `/api/v1/reading/articles/${encodeURIComponent(input.slug)}`, accept: json}),
  regents_literature: () => ({path: "/api/v1/reading/literature", accept: json}),
}

function readingList(collection: "papers" | "articles", input: Input): string {
  const query = input.after === undefined ? "" : `?${new URLSearchParams({after: input.after})}`
  return `/api/v1/reading/${collection}${query}`
}

function failure(code: Failure["error"]["code"], message: string): Failure {
  return {ok: false, error: {code, message}}
}

const invalidInput = () => failure("invalid_input", "Use the documented fields and values.")
const cancelled = () => failure("aborted", "The read was cancelled.")

function validInput(input: unknown, {properties, required}: Schema): input is Input {
  if (!input || typeof input !== "object" || Array.isArray(input)) return false
  const values = input as Record<string, unknown>
  if (required.some(key => !Object.hasOwn(values, key))) return false
  return Object.entries(values).every(([key, value]) =>
    Object.hasOwn(properties, key) &&
    typeof value === "string" &&
    (!properties[key].enum || properties[key].enum.includes(value)))
}

// Every call names its tool and this visit, so the site's log can put the call
// beside the rest of the visit (RegentsWeb.VisitLog). Neither is a credential.
function client(tool: string): Record<string, string> {
  const visit = visitId()
  return {"x-regent-client": `webmcp/${tool}`, ...(visit && {"x-regent-visit": visit})}
}

// One signal per run: it ends with the page's registration or when the host cancels.
function runSignal(lifetime: AbortSignal, client: unknown): AbortSignal {
  const host = client && typeof client === "object" ? (client as {signal?: unknown}).signal : undefined
  return host instanceof AbortSignal ? AbortSignal.any([lifetime, host]) : lifetime
}

function transport() {
  return signedTools({
    origin: window.location.origin,
    trustedOrigins: [document.querySelector<HTMLMetaElement>('meta[name="agent-request-origin"]')?.content ?? ""],
    audience: manifest.audience,
    proofHeaders: manifest.proof_headers,
    requestHeaders: client,
    // Only the signed tools are operations.
    operations: manifest.tools.filter(entry => entry.authentication === "siwa_per_request") as unknown as SignedOperation[],
  })
}

async function read(entry: Entry, input: unknown, signal: AbortSignal): Promise<unknown> {
  if (signal.aborted) return cancelled()
  if (!validInput(input, entry.input_schema)) return invalidInput()
  const target = requests[entry.name](input)
  const headers: Record<string, string> = {Accept: target.accept, ...client(entry.name)}

  let response: Response
  try {
    response = await fetch(new URL(target.path, window.location.origin), {
      headers,
      credentials: "omit",
      mode: "same-origin",
      redirect: "error",
      cache: "no-store",
      signal,
    })
  } catch {
    if (signal.aborted) return cancelled()
    // The site never heard it, so the page reports it.
    report({name: "tool.unsent", where: entry.name, outcome: "unreachable"})
    return failure("network_error", "regents.sh could not be reached.")
  }

  try {
    const body: Json = target.accept === json ? await response.json() : await response.text()
    return {ok: response.ok, status: response.status, body}
  } catch {
    return signal.aborted ? cancelled() : failure("invalid_response", "regents.sh sent an unreadable answer.")
  }
}

// Reasons that mean the tool itself is set up wrongly, not the agent's input.
const siteFaults = new Set(["invalid_operation", "invalid_path", "invalid_request_header", "unsupported_field_type"])

// The signing transport refuses with a reason such as "missing_field:after".
// The agent reads it in words; the reason itself stays in details.
function invalid(error: unknown) {
  const reason = error instanceof Error ? error.message : String(error)
  return {ok: false, error: {
    code: "invalid_request",
    message: explain(reason),
    hint: siteFaults.has(reason.split(":", 1)[0])
      ? "Use another way in, such as the API, and tell the site's team."
      : "Check the input against this tool's schema, then call the tool again.",
    details: {reason},
  }}
}

function explain(reason: string): string {
  const [kind, field] = reason.split(":", 2)
  switch (kind) {
    case "invalid_input": return "Send an object of named fields."
    case "missing_field": return `${field} is required.`
    case "invalid_field": return `${field} is not a field of this tool, or is not the kind of value it takes.`
    case "invalid_path_field": return `${field} must be a name: not empty, "." or "..".`
    case "unexpected_read_body": return "This tool reads only. Send only the fields its address names."
    case "invalid_raw_body": return "Send the body as JSON text, and nothing else."
    case "invalid_operation":
    case "invalid_path":
    case "invalid_request_header":
    case "unsupported_field_type":
      return "This tool is set up wrongly on the site, so nothing was sent."
    case "operation_unavailable": return "No signed tool has that name. Use a name from this page's tools."
    case "body_too_large": return "The input is too large."
    case "input_complexity_exceeded": return "The input has too many parts or is nested too deeply."
    case "invalid_signer_answer":
    case "proof_required":
    case "invalid_proof":
    case "incomplete_proof":
    case "body_proof_required":
    case "unexpected_body_proof":
      return "Your agent's signer gave an incomplete answer, so nothing was sent. Update regents-cli and open this site again with regents browser."
    case "untrusted_origin":
    case "insecure_origin":
      return "This page can't send signed requests."
    default: return "The input doesn't fit this tool's schema."
  }
}

// Every signed tool here reads. fetch fails with a TypeError when the network
// fails; before anything is sent, the transport refuses with a plain Error, or
// with Refused when there is no agent signer, it fails or says no, or the call
// was cancelled while it signed. Only a call the site never heard is reported.
async function signed(entry: Entry, input: unknown, signal: AbortSignal): Promise<unknown> {
  let response: Response
  try {
    response = await transport().execute(entry.name, input as Record<string, unknown>, signal)
  } catch (error) {
    if (signal.aborted) return cancelled()
    if (error instanceof Refused) return {ok: false, error: error.refusal}
    if (!(error instanceof TypeError)) return invalid(error)
    report({name: "tool.unsent", where: entry.name, outcome: "unreachable"})
    return failure("network_error", "regents.sh could not be reached.")
  }
  try {
    return {ok: response.ok, status: response.status, body: await response.json()}
  } catch {
    return signal.aborted ? cancelled() : failure("invalid_response", "regents.sh sent an unreadable answer.")
  }
}

function tool(entry: Entry, lifetime: AbortSignal): Tool {
  return {
    name: entry.name,
    title: entry.title,
    description: entry.description,
    inputSchema: entry.input_schema,
    annotations: entry.annotations,
    execute: async (input, client) => {
      const signal = runSignal(lifetime, client)
      if (signal.aborted) return cancelled()
      if (entry.authentication === "siwa_per_request") return signed(entry, input, signal)
      return read(entry, input, signal)
    },
  }
}

// One group: registered together on pageshow and withdrawn together on
// pagehide, or all at once when any one of them cannot be registered.
export function installPublicTools(documentRoot: Document = document): void {
  if (!("modelContext" in documentRoot)) return
  const context = (documentRoot as Document & {modelContext: ModelContext}).modelContext
  const status = (value: string) => { documentRoot.documentElement.dataset.webmcpStatus = value }
  const entries = manifest.tools as unknown as Entry[]
  let group: AbortController | undefined

  const start = () => {
    if (group) return
    const current = new AbortController()
    group = current
    status("registering")
    void Promise.all(entries.map(entry =>
      Promise.resolve().then(() => context.registerTool(tool(entry, current.signal), {signal: current.signal}))))
      .then(() => { if (group === current) status("ready") })
      .catch(() => {
        if (group !== current) return
        group = undefined
        current.abort()
        status("failed")
      })
  }

  window.addEventListener("pagehide", () => {
    group?.abort()
    group = undefined
    status("stopped")
  })
  window.addEventListener("pageshow", start)
  start()
}
