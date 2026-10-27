import type {Page} from "@playwright/test"

// Every ENS name, full address and short address a page shows is drawn by
// `Regent.Primitives.address`, whose words open the full address and whose icon
// copies it (founder, 2026-10-19). This lists every piece of text in the page
// and the side panel that names one outside that primitive. A 64-character
// hash, such as a block hash, is not an address and is not listed.
export async function bareAddresses(page: Page): Promise<string[]> {
  return page.evaluate(() => {
    const address = /0x[0-9a-fA-F]{40}(?![0-9a-fA-F])|0x[0-9a-fA-F]{4}(?:\.\.|…)[0-9a-fA-F]{4}|[\w-]+\.eth\b/
    const found: string[] = []
    for (const area of document.querySelectorAll("#route-content, #shell-aside")) {
      const walker = document.createTreeWalker(area, NodeFilter.SHOW_TEXT)
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        const parent = node.parentElement
        if (!parent || parent.closest("script, style, noscript, template, .rg-address")) continue
        const text = node.textContent ?? ""
        if (!address.test(text)) continue
        const where = parent.closest("[id]")
        found.push(`${where ? `#${where.id}` : parent.tagName.toLowerCase()}: ${text.trim().slice(0, 120)}`)
      }
    }
    return found
  })
}

// Every address primitive in the page and the side panel whose words or full
// address are drawn in another case or with extra spacing, as a page's
// uppercase button style would draw them.
export async function addressesOutOfCase(page: Page): Promise<string[]> {
  return page.evaluate(() => {
    const found: string[] = []
    for (const part of document.querySelectorAll("#route-content .rg-address :is(.rg-address__label, .rg-address__full), #shell-aside .rg-address :is(.rg-address__label, .rg-address__full)")) {
      const style = getComputedStyle(part)
      if (style.textTransform !== "none" || style.letterSpacing !== "normal") {
        found.push(`#${part.closest("[id]")?.id}: ${style.textTransform} ${style.letterSpacing}`)
      }
    }
    return found
  })
}
