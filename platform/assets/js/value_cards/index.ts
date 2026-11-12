/** Every value card's panel, by the name its card carries in `data-value-card`. */
import {blob} from "./panels/blob"
import {compare} from "./panels/compare"
import {fleet} from "./panels/fleet"
import {level} from "./panels/level"
import {prorata} from "./panels/prorata"
import {rewrite} from "./panels/rewrite"
import type {ValuePanel} from "./panel"

export const panels: Record<string, ValuePanel> = {
  blob,
  level,
  compare,
  fleet,
  prorata,
  rewrite,
}
