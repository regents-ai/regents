import type {Page} from "@playwright/test"
import {expect} from "./offline"

// The Stake page's guided tour (RegentsWeb.Components.Tour), as tour.spec.ts and
// stake.spec.ts read it.

// How far a ring stands outside its part: the room left round the part and the
// ring's own thickness (tour/place.ts).
const RING_OUTSIDE = 6 + 2

export async function open(page: Page) {
  await page.goto("/stake")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached()
}

export const card = (page: Page) => page.locator(".tour__card")
export const title = (page: Page) => page.locator(".tour [data-tour-title]")
export const next = (page: Page) => page.locator(".tour [data-tour-next]")

// Where the ring and the card stand against the step's part: how far the ring is
// from standing RING_OUTSIDE round the part on every side (0 when it does), whether
// the card covers the part, whether it lies wholly on the screen, and which links
// and buttons of the page on the screen that the card does not cover a press at
// their middle fails to reach (none: the dimming takes no presses).
export function standing(page: Page, selector: string) {
  return page.evaluate(
    ([selector, outside]) => {
      const ring = [...document.querySelectorAll(".tour__edge > .tour__piece")].map(piece => piece.getBoundingClientRect())
      const shown = document.querySelector(".tour__card")!.getBoundingClientRect()
      const onScreen = shown.left >= 0 && shown.top >= 0 && shown.right <= innerWidth && shown.bottom <= innerHeight
      const under = (at: DOMRect) =>
        shown.left < at.right && at.left < shown.right && shown.top < at.bottom && at.top < shown.bottom
      const blocked = [...document.querySelectorAll("#regent-staking :is(a[href], button)")]
        .map(control => [control, control.getBoundingClientRect()] as const)
        .filter(([, at]) => at.width > 0 && at.top >= 0 && at.left >= 0 && at.bottom <= innerHeight && at.right <= innerWidth)
        .filter(([, at]) => !under(at))
        .filter(([control, at]) => !control.contains(document.elementFromPoint(at.x + at.width / 2, at.y + at.height / 2)))
        .map(([control]) => control.id || control.textContent!.trim())
      const overflow = document.documentElement.scrollWidth > innerWidth

      const part = document.querySelector(selector)!.getBoundingClientRect()
      const outer = {
        left: Math.min(...ring.map(line => line.left)),
        top: Math.min(...ring.map(line => line.top)),
        right: Math.max(...ring.map(line => line.right)),
        bottom: Math.max(...ring.map(line => line.bottom)),
      }
      const ringOff = Math.max(
        Math.abs(outer.left - (part.left - outside)),
        Math.abs(outer.top - (part.top - outside)),
        Math.abs(outer.right - (part.right + outside)),
        Math.abs(outer.bottom - (part.bottom + outside)),
      )
      return {ringOff, covers: under(part), onScreen, blocked, overflow}
    },
    [selector, RING_OUTSIDE] as const,
  )
}
