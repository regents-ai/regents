/**
 * Where the guided tour's pieces go on the screen (hooks/tour.ts): the hole in
 * the dimming round the part a step points at, the ring at the hole's edge and
 * the card beside it. Everything is in CSS pixels from the screen's top left.
 */

export type Box = {x: number; y: number; w: number; h: number}
export type Size = {w: number; h: number}
export type Spot = {x: number; y: number}

/** The room left between a part and its ring. */
export const ROOM = 6
/** How thick the ring is. */
export const EDGE = 2
/** The least space between the card and the screen's edge. */
const MARGIN = 16
/** The space between the ring and the card. */
const GAP = 12

/** A box made `by` larger on every side. */
export const grow = (box: Box, by: number): Box => ({
  x: box.x - by,
  y: box.y - by,
  w: box.w + 2 * by,
  h: box.h + 2 * by,
})

/** The hole round a part, with ROOM to spare on every side. */
export const holeAround = (part: Box): Box => grow(part, ROOM)

/** No hole at all: a point in the middle of the screen, so the dimming covers it whole. */
export const noHole = (view: Size): Box => ({x: view.w / 2, y: view.h / 2, w: 0, h: 0})

/** Part of the way from one box to another; `t` runs from 0 to 1. */
export const mixBox = (from: Box, to: Box, t: number): Box => ({
  x: from.x + (to.x - from.x) * t,
  y: from.y + (to.y - from.y) * t,
  w: from.w + (to.w - from.w) * t,
  h: from.h + (to.h - from.h) * t,
})

export const mixSpot = (from: Spot, to: Spot, t: number): Spot => ({
  x: from.x + (to.x - from.x) * t,
  y: from.y + (to.y - from.y) * t,
})

/**
 * The dimming as four boxes round the hole (above, below, left, right) and the
 * ring as four lines just outside it, in the same order. Every edge falls on a
 * whole pixel, so the pieces meet without a seam. A ring shrinks to nothing as
 * its hole does.
 */
export function pieces(hole: Box, view: Size): {shade: Box[]; ring: Box[]} {
  const left = Math.round(Math.min(Math.max(hole.x, 0), view.w))
  const top = Math.round(Math.min(Math.max(hole.y, 0), view.h))
  const right = Math.round(Math.min(Math.max(hole.x + hole.w, left), view.w))
  const bottom = Math.round(Math.min(Math.max(hole.y + hole.h, top), view.h))
  const edge = Math.round(EDGE * Math.min(1, hole.w / 8, hole.h / 8))
  const [w, h] = [right - left, bottom - top]

  return {
    shade: [
      {x: 0, y: 0, w: view.w, h: top},
      {x: 0, y: bottom, w: view.w, h: view.h - bottom},
      {x: 0, y: top, w: left, h},
      {x: right, y: top, w: view.w - right, h},
    ],
    ring: [
      {x: left - edge, y: top - edge, w: w + 2 * edge, h: edge},
      {x: left - edge, y: bottom, w: w + 2 * edge, h: edge},
      {x: left - edge, y: top, w: edge, h},
      {x: right, y: top, w: edge, h},
    ],
  }
}

const overlaps = (a: Box, b: Box) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h

const inside = (spot: Spot, card: Size, view: Size) =>
  spot.x >= 0 && spot.y >= 0 && spot.x + card.w <= view.w && spot.y + card.h <= view.h

const clamp = (value: number, low: number, high: number) => Math.min(Math.max(value, low), Math.max(low, high))

/**
 * Where the card goes: beside the hole on a wide screen, below it first; along
 * the screen's foot on a phone (`docked`), or along its top when the hole is
 * down there. A step with no hole has its card in the middle of the screen,
 * or at the middle of its foot, or along the foot on a phone. The card keeps
 * off the hole and its ring, and off every box in `clear` (the controls that
 * must stay in reach while the tour shows, such as a wallet button), wherever
 * there is room for that.
 */
export function cardSpot(hole: Box | undefined, card: Size, view: Size, docked: boolean, clear: Box[] = []): Spot {
  const ring = hole && {x: hole.x - EDGE, y: hole.y - EDGE, w: hole.w + 2 * EDGE, h: hole.h + 2 * EDGE}
  const foot = {x: MARGIN, y: view.h - card.h - MARGIN}
  const head = {x: MARGIN, y: MARGIN}
  const middle = (view.w - card.w) / 2

  if (docked) return choose(ring ? [foot, head] : [foot], card, view, ring, clear)
  if (!ring) return choose([{x: middle, y: (view.h - card.h) / 2}, {x: middle, y: foot.y}], card, view, ring, clear)

  const alongX = clamp(ring.x, MARGIN, view.w - card.w - MARGIN)
  const alongY = clamp(ring.y, MARGIN, view.h - card.h - MARGIN)
  const corner = (x: number, y: number) => ({x: x ? view.w - card.w - MARGIN : MARGIN, y: y ? view.h - card.h - MARGIN : MARGIN})

  return choose(
    [
      {x: alongX, y: ring.y + ring.h + GAP},
      {x: alongX, y: ring.y - GAP - card.h},
      {x: ring.x + ring.w + GAP, y: alongY},
      {x: ring.x - GAP - card.w, y: alongY},
      corner(1, 1),
      corner(0, 1),
      corner(1, 0),
      corner(0, 0),
    ],
    card,
    view,
    ring,
    clear,
  )
}

/** Whether a card docked along the screen's foot would lie over the hole's ring. */
export const underFoot = (hole: Box, card: Size, view: Size) => hole.y + hole.h + EDGE > view.h - card.h - MARGIN

// The first place on the screen that keeps off the ring and the controls; then
// the first that keeps off the controls, since they must stay in reach; then
// the first that keeps off the ring; then the first there is.
function choose(spots: Spot[], card: Size, view: Size, ring: Box | undefined, clear: Box[]): Spot {
  const box = (spot: Spot) => ({...spot, ...card})
  const offRing = (spot: Spot) => inside(spot, card, view) && !(ring && overlaps(box(spot), ring))
  const offControls = (spot: Spot) => inside(spot, card, view) && !clear.some(control => overlaps(box(spot), control))
  return (
    spots.find(spot => offRing(spot) && offControls(spot)) ??
    spots.find(offControls) ??
    spots.find(offRing) ??
    spots[0]
  )
}
