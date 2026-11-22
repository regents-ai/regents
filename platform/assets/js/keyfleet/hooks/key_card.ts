/**
 * A Key's card (`KeyfleetWeb.Components.KeyCard`). Under a mouse it turns a
 * little toward the pointer and a soft light follows the pointer across its
 * foil; both settle when the pointer leaves, and once level the card keeps no
 * turn of its own. A finger, a keyboard or less motion gets the card as it is.
 */
import {createAnimatable, createScope, type AnimatableObject, type Scope} from "animejs"
import {EASE_OUT, still} from "./motion/shared"

type KeyCardHook = {el: HTMLElement; scope?: Scope; release?: () => void}

const finePointer = () => matchMedia("(hover: hover) and (pointer: fine)").matches

export const KeyCardTurn = {
  mounted(this: KeyCardHook) {
    const root = this.el
    const tilt = root.querySelector<HTMLElement>("[data-key-tilt]")!
    const light = root.querySelector<HTMLElement>("[data-key-light]")!
    let turn: AnimatableObject | undefined
    let glow: AnimatableObject | undefined

    const scope = createScope({root, mediaQueries: {reduced: "(prefers-reduced-motion: reduce)"}})
    this.scope = scope.add(() => {
      if (scope.matches.reduced || !finePointer()) return
      const level = createAnimatable(tilt, {
        rotateX: 0,
        rotateY: 0,
        duration: 420,
        ease: EASE_OUT,
        onComplete: () => {
          if (level.rotateX() === 0 && level.rotateY() === 0) tilt.style.removeProperty("transform")
        },
      })
      const shine = createAnimatable(light, {
        x: {unit: "%", duration: 240},
        y: {unit: "%", duration: 240},
        opacity: 300,
        ease: EASE_OUT,
        onComplete: () => {
          if (shine.opacity() === 0) light.style.removeProperty("transform")
        },
      })
      turn = level
      glow = shine
      return () => {
        tilt.style.removeProperty("transform")
        light.style.removeProperty("transform")
        light.style.removeProperty("opacity")
        turn = undefined
        glow = undefined
      }
    })

    const onMove = (event: PointerEvent) => {
      if (!turn || !glow || !event.isPrimary || event.pointerType !== "mouse" || still(root)) return
      const box = tilt.getBoundingClientRect()
      const x = Math.min(1, Math.max(0, (event.clientX - box.left) / box.width))
      const y = Math.min(1, Math.max(0, (event.clientY - box.top) / box.height))
      turn.rotateY((x - 0.5) * 12)
      turn.rotateX((0.5 - y) * 9)
      // The light is twice the card's size, centred on the pointer.
      glow.x((x - 1) * 50)
      glow.y((y - 1) * 50)
      glow.opacity(1)
    }
    const onLeave = () => {
      turn?.rotateX(0)
      turn?.rotateY(0)
      glow?.opacity(0)
    }
    const events = new AbortController()
    root.addEventListener("pointermove", onMove, {signal: events.signal, passive: true})
    root.addEventListener("pointerleave", onLeave, {signal: events.signal, passive: true})
    this.release = () => events.abort()
  },
  destroyed(this: KeyCardHook) {
    this.release?.()
    this.scope?.revert()
  },
}
