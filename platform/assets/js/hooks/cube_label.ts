import {animate, createScope, type Scope} from "animejs"

type CubeLabelHook = {
  el: HTMLElement
  scope?: Scope
  onPointing?: (event: Event) => void
}

/**
 * "Human Browsing" over the world cube, shown while the pointer is on the cube.
 * Where nothing hovers, the stylesheet keeps it shown.
 */
export const CubeLabel = {
  mounted(this: CubeLabelHook) {
    const label = this.el.querySelector<HTMLElement>(".rl-cube-label")!
    const still = window.matchMedia("(prefers-reduced-motion: reduce)")
    const hoverless = window.matchMedia("(hover: none)")
    let shown = false

    const scope = createScope({root: this.el})
    this.scope = scope
    scope.add(() => {
      scope.add("label", (show: boolean) => {
        animate(label, {
          opacity: show ? 1 : 0,
          translateY: show ? 0 : 8,
          duration: still.matches ? 0 : show ? 520 : 320,
          ease: show ? "outCubic" : "inCubic",
        })
      })
    })

    this.onPointing = event => {
      const {pointing} = (event as CustomEvent<{pointing: boolean}>).detail
      if (hoverless.matches || pointing === shown) return
      shown = pointing
      this.scope!.methods.label!(shown)
    }
    this.el.addEventListener("cube:pointing", this.onPointing)
  },
  destroyed(this: CubeLabelHook) {
    if (this.onPointing) this.el.removeEventListener("cube:pointing", this.onPointing)
    this.scope?.revert()
  },
}
