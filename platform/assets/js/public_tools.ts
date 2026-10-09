// WebMCP (document.modelContext): the read tools every regents.sh page offers.
// Every tool is described once, in priv/tool_manifest.json; this file adds only
// the request each one makes. None of them opens a wallet or signs.
import manifest from "../../priv/tool_manifest.json" with {type: "json"}
import {signedTools, type SignedOperation, type SignedInput} from "../vendor/regent_agent_access/signed_tools"

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
  scope: "site" | "page"
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
const requests: Record<string, (input: Input) => Request> = {
  regents_about: input => ({path: `/${input.page}`, accept: "text/markdown"}),
  regents_products: () => ({path: "/api/v1/products", accept: json}),
  regents_product: input => ({path: `/api/v1/products/${encodeURIComponent(input.slug)}`, accept: json}),
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
    operations: manifest.tools.map(entry => ({...entry,
      input_schema: "operation_input_schema" in entry ? entry.operation_input_schema : entry.input_schema,
    })) as unknown as SignedOperation[],
  })
}

async function read(entry: Entry, input: unknown, signal: AbortSignal): Promise<unknown> {
  if (signal.aborted) return cancelled()
  if (!validInput(input, entry.input_schema)) return invalidInput()
  const target = requests[entry.name](input)
  const headers: Record<string, string> = {Accept: target.accept}

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
    return signal.aborted ? cancelled() : failure("network_error", "regents.sh could not be reached.")
  }

  try {
    const body: Json = target.accept === json ? await response.json() : await response.text()
    return {ok: response.ok, status: response.status, body}
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
      if (entry.name === "prepare_agent_request") {
        try {
          const args = input as {operation: string; input: Record<string, string>}
          return {ok: true, request: transport().prepare(args.operation, args.input)}
        } catch {
          return invalidInput()
        }
      }
      if (entry.authentication === "siwa_per_request") {
        try {
          const response = await transport().execute(entry.name, input as SignedInput, signal)
          return {ok: response.ok, status: response.status, body: await response.json()}
        } catch {
          return signal.aborted ? cancelled() : {ok: false, error: {
            code: "signed_request_failed",
            message: "Prepare the request and sign its exact bytes with your existing SIWA signer for regents. Use fresh proof; if no signer is available, report that blocker.",
          }}
        }
      }
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
  const entries = (manifest.tools as unknown as Entry[]).filter(entry => entry.scope === "site")
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
