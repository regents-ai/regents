import {animate, createScope, stagger, type Scope} from "animejs"

import manifest from "../../../priv/tool_manifest.json" with {type: "json"}

type Schema = {type: "object"; properties: Record<string, unknown>; required: string[]; additionalProperties: false}
type Entry = {
  name: string
  title: string
  description: string
  input_schema: Schema
  annotations: Record<string, boolean>
  route: string
  scope: string
}
type Tool = {
  name: string
  title: string
  description: string
  inputSchema: Schema
  annotations: Record<string, boolean>
  execute(input: unknown, client?: {signal?: AbortSignal}): Promise<Reply>
}
type ModelContext = {registerTool(tool: Tool, options: {signal: AbortSignal}): Promise<void> | void}

type Reply =
  | {ok: true; status: number; data: unknown}
  | {ok: false; status?: number; error: {code: string; message: string; hint?: string}}

// JSON imports widen every literal, so the manifest is read as the shape it is written in.
const manifestTools = manifest.tools as unknown as Entry[]

// The card's list, read as anyone may read it, with the site's refusal handed on as it came.
async function read(path: string, signal: AbortSignal | undefined): Promise<Reply> {
  try {
    const response = await fetch(path, {
      headers: {Accept: "application/json"},
      credentials: "omit",
      cache: "no-store",
      redirect: "error",
      signal,
    })
    const answer = await response.json()
    return response.ok
      ? {ok: true, status: response.status, data: answer}
      : {ok: false, status: response.status, error: answer.error}
  } catch (_error) {
    return signal?.aborted
      ? {ok: false, error: {code: "cancelled", message: "The read was cancelled; nothing changed."}}
      : {ok: false, error: {code: "unreachable", message: "The site could not be reached. Try again."}}
  }
}

type TwinCubeHook = {
  el: HTMLElement
  scope?: Scope
  registration?: AbortController
  onPointing?: (event: Event) => void
}

/**
 * The twin cube's page: "Human Browsing" over the world cube and "Agentic
 * WebMCP" over the code cube, shown together while the pointer is on either
 * cube, and the six browser tools that open the code cube's cards for an agent
 * the way a click on a face does for a person.
 */
export const TwinCube = {
  mounted(this: TwinCubeHook) {
    const labels = this.el.querySelectorAll<HTMLElement>("[data-twin-label]")
    const still = window.matchMedia("(prefers-reduced-motion: reduce)")
    // Where nothing hovers, the stylesheet keeps both names shown.
    const hoverless = window.matchMedia("(hover: none)")
    const pointing = new Set<EventTarget>()
    let shown = false

    const scope = createScope({root: this.el})
    this.scope = scope
    scope.add(() => {
      scope.add("labels", (show: boolean) => {
        animate(labels, {
          opacity: show ? 1 : 0,
          translateY: show ? 0 : 8,
          duration: still.matches ? 0 : show ? 520 : 320,
          delay: show ? stagger(90) : 0,
          ease: show ? "outCubic" : "inCubic",
        })
      })
    })

    this.onPointing = event => {
      const {pointing: on} = (event as CustomEvent<{pointing: boolean}>).detail
      if (on) pointing.add(event.target!)
      else pointing.delete(event.target!)
      if (hoverless.matches || pointing.size > 0 === shown) return
      shown = pointing.size > 0
      this.scope!.methods.labels!(shown)
    }
    this.el.addEventListener("cube:pointing", this.onPointing)

    TwinCube.register.call(this)
  },
  reconnected(this: TwinCubeHook) {
    TwinCube.register.call(this)
  },
  destroyed(this: TwinCubeHook) {
    this.registration?.abort()
    if (this.onPointing) this.el.removeEventListener("cube:pointing", this.onPointing)
    this.scope?.revert()
  },

  // One registration for the six tools: a new one replaces the last, and a
  // failure removes all six, so the page never holds half a set.
  register(this: TwinCubeHook) {
    const status = this.el.dataset
    if (!("modelContext" in document)) {
      status.webmcpStatus = "unsupported"
      return
    }
    const context = (document as Document & {modelContext: ModelContext}).modelContext
    this.registration?.abort()
    const current = new AbortController()
    this.registration = current
    const root = this.el

    // The tools of the page the twin cube is on.
    const entries = manifestTools.filter(entry => entry.scope === window.location.pathname)
    const tools: Tool[] = entries.map(entry => {
      const path = entry.route.split(" ")[1]!
      const site = path.split("/").at(-1)!
      return {
        name: entry.name,
        title: entry.title,
        description: entry.description,
        inputSchema: entry.input_schema,
        annotations: entry.annotations,
        async execute(_input, client) {
          // The card opens on the page as it would for a click on its face.
          root.querySelector<HTMLButtonElement>(`[data-code-site="${site}"]`)!.click()
          return read(path, client?.signal)
        },
      }
    })

    Promise.all(tools.map(tool => Promise.resolve().then(() => context.registerTool(tool, {signal: current.signal}))))
      .then(() => {
        if (this.registration === current) status.webmcpStatus = "connected"
      })
      .catch((error: unknown) => {
        current.abort()
        if (this.registration !== current) return
        status.webmcpStatus = "error"
        console.warn("The twin cube's browser tools could not be offered.", error)
      })
  },
}
