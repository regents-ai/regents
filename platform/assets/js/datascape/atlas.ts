/**
 * The words the datascape shows, drawn once on a canvas in the site's code
 * face: four pages of text that panels scroll through, and a dozen short
 * labels. The renderer keeps the ink alone, one byte for each texel.
 */
import {ATLAS, LABELS, labelRect, random} from "./world"

/** Texels in one world unit. */
const SCALE = ATLAS.texels / ATLAS.span
/** A page's letters and the room each line takes, in world units. Sixty-four lines fill a page exactly, so it repeats without a seam. */
const LETTER = 8
const LINE = 12
const LINES = ATLAS.pageHeight / LINE

const HEX = "0123456789ABCDEF"
const WORDS = [
  "SYNC",
  "PHASE",
  "CONNECT",
  "SEQUENCE",
  "PACKET",
  "LOCK",
  "CIRCUIT",
  "RELAY",
  "NODE",
  "TRACE",
  "FRAME",
  "BUFFER",
  "CARRIER",
  "CHANNEL",
  "DECODE",
  "VERIFY",
  "HANDSHAKE",
  "OFFSET",
] as const
const MARKS = [">>", "--", "::", "//", "##", "=>"] as const

/** One page's lines, each kind of page written its own way. */
function pageLines(page: number): string[] {
  const next = random(0x51a7 + page * 977)
  const pick = <T>(from: readonly T[]): T => from[Math.floor(next() * from.length)]!
  const hex = (digits: number) => Array.from({length: digits}, () => pick([...HEX])).join("")
  return Array.from({length: LINES}, (_, line) => {
    switch (page) {
      // A dump of bytes, address first.
      case 0:
        return `0x${hex(4)}: ${Array.from({length: 12}, () => hex(2)).join(" ")}`
      // A log: a mark, a few words and a number, with a gap now and then.
      case 1:
        return next() < 0.12 ? "" : `${pick(MARKS)} ${pick(WORDS)} ${pick(WORDS)} ${hex(2)}${next() < 0.4 ? ` OK` : ""}`
      // Short ragged lines, set in from the left, like a listing.
      case 2:
        return `${" ".repeat(Math.floor(next() * 4) * 2)}${pick(WORDS).toLowerCase()}.${pick(WORDS).toLowerCase()}(${hex(3)})`.slice(0, 20 + Math.floor(next() * 28))
      // Solid rules of different lengths.
      default:
        return line % 5 === 4 ? "" : pick(["=", "-", "#", ":"]).repeat(8 + Math.floor(next() * 40))
    }
  })
}

/** The atlas's ink: `ATLAS.texels` squared bytes, row by row from the top. */
export async function drawAtlas(): Promise<Uint8Array<ArrayBuffer>> {
  const family = getComputedStyle(document.documentElement).getPropertyValue("--font-family-mono")
  // The face is one of the site's own and usually loaded already; this waits when it is not.
  await document.fonts.load(`${LETTER}px ${family}`)

  const canvas = document.createElement("canvas")
  canvas.width = ATLAS.texels
  canvas.height = ATLAS.texels
  const context = canvas.getContext("2d", {willReadFrequently: true})!
  context.scale(SCALE, SCALE)
  context.fillStyle = "#fff"
  context.textBaseline = "top"

  context.font = `${LETTER}px ${family}`
  for (let page = 0; page < ATLAS.pages; page++) {
    const left = page * ATLAS.pageWidth
    context.save()
    context.beginPath()
    context.rect(left, 0, ATLAS.pageWidth, ATLAS.pageHeight)
    context.clip()
    for (const [line, words] of pageLines(page).entries()) context.fillText(words, left + 4, line * LINE + 2)
    context.restore()
  }

  context.font = `${ATLAS.labelHeight * 0.8}px ${family}`
  for (const [index, words] of LABELS.entries()) {
    const [left, top, right] = labelRect(index)
    // A label's box was sized for its letters; a wider face is pressed to fit it.
    context.fillText(words, left * ATLAS.span + 4, top * ATLAS.span + ATLAS.labelHeight * 0.12, (right - left) * ATLAS.span - 8)
  }

  const pixels = context.getImageData(0, 0, ATLAS.texels, ATLAS.texels).data
  const ink = new Uint8Array(ATLAS.texels * ATLAS.texels)
  for (let texel = 0; texel < ink.length; texel++) ink[texel] = pixels[texel * 4 + 3]!
  return ink
}
