/**
 * The light and dark theme switch (`RegentsWeb.Components.Shell.theme_toggle/1`).
 *
 * The switch is a real button with the role of a switch: on is the light theme.
 * A press, Enter or Space turns it, and the page's theme changes at once, never
 * waiting for anything drawn.
 *
 * Over the knob's way lies a particle field (hooks/particle_field.ts), driven
 * from here: the moon at night, the sun by day. A press flies the grains from
 * the one to the other while the knob glides across on the design system's
 * on-screen curve; a second press mid-flight turns them round from wherever
 * they are. A key turns it at once, the knob and the grains alike, as every
 * keyboard-driven control here does. Until the grains have drawn, and wherever
 * they never do, the server's drawings show and the knob moves at once.
 *
 * The knob's position is one number, p: 0 at night on the left, 1 by day on the
 * right, which the stylesheet reads from `--theme-switch-p`.
 *
 * Every switch on the page follows the theme on screen, whoever changed it, and
 * moves to match.
 */
import {createAnimatable} from "animejs"

import {chooseTheme, showingTheme, watchTheme, type Theme} from "../theme"
import {EASE_IN_OUT, SLOW, byPointer, lastInputByPointer, still} from "./motion/shared"
import {createParticleField, type ParticleFieldController} from "./particle_field"

export type ThemeSwitchController = Pick<ParticleFieldController, "mount" | "pause" | "resume" | "destroy">

const sideOf = (theme: Theme) => (theme === "light" ? 1 : 0)

export function createThemeSwitch(root: HTMLElement): ThemeSwitchController {
  const button = root.querySelector<HTMLButtonElement>("[role='switch']")!
  const fieldRoot = root.querySelector<HTMLElement>(".particle-field")!
  const field = createParticleField(fieldRoot)

  let shown = showingTheme()
  // What Anime.js moves: the knob, between 0 and 1.
  const knob = {p: sideOf(shown) as number}
  const render = () => root.style.setProperty("--theme-switch-p", (Math.round(knob.p * 10000) / 10000).toString())
  const motion = createAnimatable(knob, {p: 0, onUpdate: render})

  /** Shows a theme: the switch's state, the knob, and the moon or the sun, flown to or at once. */
  const show = (theme: Theme, animated: boolean) => {
    shown = theme
    const side = sideOf(theme)
    button.setAttribute("aria-checked", String(side === 1))
    field.show(theme === "light" ? "sun" : "moon", side, animated)
    // The knob glides only while the grains draw, so the server's drawing never waits on an empty track.
    if (animated && fieldRoot.dataset.particleReady === "true" && !still(root)) {
      motion.p(side, SLOW, EASE_IN_OUT)
    } else {
      motion.p(side, 0, "linear")
      knob.p = side
      render()
    }
  }

  const onClick = (event: MouseEvent) => {
    const next: Theme = shown === "light" ? "dark" : "light"
    show(next, byPointer(event))
    chooseTheme(next)
  }

  const events = new AbortController()
  let stopWatchingTheme = () => {}

  return {
    mount() {
      show(shown, false)
      button.addEventListener("click", onClick, {signal: events.signal})
      stopWatchingTheme = watchTheme(theme => {
        if (theme !== shown) show(theme, lastInputByPointer())
      })
      field.mount()
    },
    pause() {
      field.pause()
    },
    resume() {
      field.resume()
    },
    destroy() {
      events.abort()
      stopWatchingTheme()
      field.destroy()
      motion.revert()
    },
  }
}

type ThemeSwitchHook = {el: HTMLElement; controller?: ThemeSwitchController}

export const ThemeSwitch = {
  mounted(this: ThemeSwitchHook) {
    this.controller = createThemeSwitch(this.el)
    this.controller.mount()
  },
  disconnected(this: ThemeSwitchHook) {
    this.controller?.pause()
  },
  reconnected(this: ThemeSwitchHook) {
    this.controller?.resume()
  },
  destroyed(this: ThemeSwitchHook) {
    this.controller?.destroy()
    this.controller = undefined
  },
}
