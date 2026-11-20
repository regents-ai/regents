/**
 * Techtree's Copy page control (`RegentsWeb.Techtree.PageCopy`): "Copy page"
 * puts the page on the clipboard as Markdown, and "View as Markdown" opens it
 * as plain text in a new tab.
 */
import {deny} from "../hooks/motion/press"
import {mountPageCopyButton, type CopyHook} from "./copy_feedback"

// One page, spoken as Markdown. The serializer walks exactly what the reader
// sees — headings, prose, lists, terms, commands, fingerprints — so the copy
// can never drift from the page, release values included. Nothing is sent
// anywhere: the result goes to the clipboard, or into a new tab the reader
// opened themselves.
const isElement = (node: Node): node is Element => node.nodeType === Node.ELEMENT_NODE

function pageAsMarkdown(root: Element) {
  const lines: string[] = []

  const text = (node: Element) => node.textContent.replace(/\s+/g, " ").trim()

  const inline = (node: Element): string => {
    let out = ""
    for (const child of node.childNodes) {
      if (child.nodeType === Node.TEXT_NODE) {
        out += child.textContent!.replace(/\s+/g, " ")
      } else if (isElement(child)) {
        const tag = child.tagName.toLowerCase()
        if (tag === "code" || child.classList.contains("digest")) {
          out += "`" + text(child) + "`"
        } else if (tag === "a") {
          const href = child.getAttribute("href") || ""
          const absolute = new URL(href, window.location.href).href
          out += "[" + text(child) + "](" + absolute + ")"
        } else if (tag === "strong" || tag === "b") {
          out += "**" + text(child) + "**"
        } else {
          out += inline(child)
        }
      }
    }
    return out
  }

  const walk = (node: Element) => {
    for (const child of node.children) {
      if (child.closest("[data-markdown-skip]")) continue
      const tag = child.tagName.toLowerCase()

      if (/^h[1-6]$/.test(tag)) {
        lines.push("#".repeat(Number(tag[1])) + " " + text(child), "")
      } else if (tag === "p") {
        const line = inline(child).replace(/\s+/g, " ").trim()
        if (line) lines.push(line, "")
      } else if (tag === "pre") {
        lines.push("```", child.textContent.trim(), "```", "")
      } else if (tag === "ul" || tag === "ol") {
        Array.from(child.children).forEach((item, index) => {
          const marker = tag === "ol" ? `${index + 1}.` : "-"
          lines.push(marker + " " + inline(item).replace(/\s+/g, " ").trim())
        })
        lines.push("")
      } else if (tag === "table") {
        const rows = Array.from(child.querySelectorAll("tr"), row =>
          Array.from(row.children, cell => inline(cell).replace(/\s+/g, " ").trim()))
        const line = (cells: string[]) => "| " + cells.join(" | ") + " |"
        if (rows.length) {
          lines.push(line(rows[0]), line(rows[0].map(() => "---")), ...rows.slice(1).map(line), "")
        }
      } else if (tag === "dl") {
        let term: string | null = null
        for (const part of child.children) {
          if (part.tagName === "DT") term = text(part)
          if (part.tagName === "DD" && term !== null) {
            lines.push("- **" + term + "**: " + inline(part).replace(/\s+/g, " ").trim())
            term = null
          }
        }
        lines.push("")
      } else {
        walk(child)
      }
    }
  }

  walk(root)
  return lines.join("\n").replace(/\n{3,}/g, "\n\n").trim() + "\n"
}

const docsRoot = () => document.querySelector("[data-markdown-root]") ?? document.querySelector("main")!

export const CopyCommandPage = {
  mounted(this: CopyHook) {
    mountPageCopyButton(this, () => pageAsMarkdown(docsRoot()), {refuse: deny})
  },
}

export const CopyCommandPageView = {
  mounted(this: {el: HTMLElement}) {
    this.el.addEventListener("click", () => {
      const markdown = pageAsMarkdown(docsRoot())
      const tab = window.open("", "_blank")
      if (!tab) return
      tab.document.title = "Techtree docs as Markdown"
      const pre = tab.document.createElement("pre")
      pre.style.cssText = "white-space:pre-wrap;font-family:ui-monospace,monospace;padding:2rem;max-width:60rem;margin:0 auto;"
      pre.textContent = markdown
      tab.document.body.appendChild(pre)
    })
  },
}
