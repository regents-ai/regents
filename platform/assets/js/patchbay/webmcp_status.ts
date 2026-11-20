// The WebMCP guide's status line (/patchbay/webmcp, `#pb-webmcp-status`), as
// patchbay.help paints it (its webmcp/agent_setup.ts). It says only whether the
// browser offers WebMCP (`document.modelContext`, the draft's only entry point),
// never that Patchbay's tools reached an agent, and opens the browser alternatives
// when WebMCP is missing. Until this runs, the line says it cannot tell yet.
export function mountWebMCPStatus() {
  const root = document.getElementById("pb-webmcp-status")
  if (!root) return

  const detected = Boolean((document as Document & {modelContext?: unknown}).modelContext)
  const text = detected ? "WebMCP detected in this browser" : "WebMCP was not detected in this browser."
  root.querySelector("[data-pb-webmcp]")?.replaceChildren(dot(detected), text)

  const missing = root.querySelector<HTMLElement>("[data-pb-webmcp-missing]")
  if (missing) missing.hidden = detected
}

function dot(full: boolean): HTMLSpanElement {
  const mark = document.createElement("span")
  mark.className = full ? "pb-setup-dot is-full" : "pb-setup-dot is-empty"
  mark.setAttribute("aria-hidden", "true")
  return mark
}
