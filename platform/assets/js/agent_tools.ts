import {visitId} from "./visit_log"

type Tool = {name: string; title: string; description: string}
type Step = {title: string; copy: string; command: string}
type EverySite = {
  sites: {site: string; tools: Tool[]}[]
  unreachable: string[]
  connection: {guide: string; steps: Step[]}
}

// Each dialog's read of every site: under way, or done. A failed read is
// forgotten, so the next opening asks again.
const reads = new WeakMap<HTMLDialogElement, Promise<void>>()

/**
 * The list of tools agents see (`AgentTools`), on every page that shows its
 * button, from one listener on the document. The button opens the dialog its
 * `aria-controls` names; the dialog's X, Escape, or a press on its backdrop,
 * which lands on the dialog itself, closes it. Each opening reads every Regent
 * site's tools for the copy-all button, until one read succeeds.
 */
export function installAgentTools() {
  document.addEventListener("click", event => {
    const target = event.target instanceof Element ? event.target : null
    const opener = target?.closest<HTMLButtonElement>("[data-agent-tools-open]")
    const dialog = opener && document.getElementById(opener.getAttribute("aria-controls") ?? "")
    if (dialog instanceof HTMLDialogElement) {
      dialog.showModal()
      if (!reads.has(dialog)) reads.set(dialog, readEverySite(dialog))
      return
    }

    const shown = target?.closest<HTMLDialogElement>("dialog[data-agent-tools]")
    if (shown && (target === shown || target?.closest("[data-agent-tools-close]"))) shown.close()
  })
}

async function readEverySite(dialog: HTMLDialogElement): Promise<void> {
  const button = dialog.querySelector<HTMLButtonElement>("[data-agent-tools-copy-all]")!
  const note = dialog.querySelector<HTMLElement>("[data-agent-tools-note]")!
  const all = dialog.querySelector<HTMLElement>("[data-agent-tools-all]")!
  note.textContent = "Reading every site's tools…"
  // It sends no cookies, so it names this visit for the site's log (RegentsWeb.VisitLog).
  const visit = visitId()
  try {
    const response = await fetch("/api/v1/site-tools", {
      headers: {Accept: "application/json", ...(visit && {"x-regent-visit": visit})},
      credentials: "omit",
      cache: "no-store",
      redirect: "error",
    })
    if (!response.ok) throw new Error(`site tools answered ${response.status}`)
    const every = (await response.json()) as EverySite
    all.textContent = markdown(every)
    button.disabled = false
    note.textContent = summary(every)
  } catch {
    reads.delete(dialog)
    note.textContent = "Couldn't read the sites. Close and open this window to try again."
  }
}

function summary({sites, unreachable}: EverySite): string {
  const tools = sites.reduce((count, site) => count + site.tools.length, 0)
  const read = unreachable.length === 0 ? `${sites.length} sites` : `${sites.length} of ${sites.length + unreachable.length} sites`
  return `${tools} tools from ${read}`
}

// Every site's tools as Markdown, one section for each site, then how an agent
// connects to siwa-server.
function markdown({sites, unreachable, connection}: EverySite): string {
  const read = sites.map(({site, tools}) =>
    tools.length === 0
      ? `## ${site}\n\n${site} offers agents no tools right now.`
      : `## ${site}\n\n${tools.length} WebMCP tools\n\n` +
        tools.map(tool => `### ${tool.title}\n\n\`${tool.name}\`\n\n${tool.description}`).join("\n\n"),
  )
  const missing = unreachable.map(site => `## ${site}\n\n${site}'s tools could not be read right now.`)
  const steps = connection.steps
    .map(step => `### ${step.title}\n\n${step.copy}\n\n\`\`\`sh\n${step.command}\n\`\`\``)
    .join("\n\n")
  const siwa = `## siwa-server\n\nOne sign-in for agents on every Regent site.\n\n${steps}\n\nThe whole guide: ${connection.guide}`
  return `# WebMCP tools on every Regent site\n\n${[...read, ...missing, siwa].join("\n\n")}\n`
}
