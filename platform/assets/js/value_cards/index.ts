/**
 * Every value card's panel, by the name its card carries in `data-value-card`.
 * This site's own six come with the renderer. A product page shows that
 * product's own six, kept in `panels/<product>/` and listed in its `index.ts`:
 * such a card names its panel `<product>/<name>`, and the product's six arrive
 * together the first time its page shows one.
 */
import {blob} from "./panels/blob"
import {compare} from "./panels/compare"
import {fleet} from "./panels/fleet"
import {level} from "./panels/level"
import {prorata} from "./panels/prorata"
import {rewrite} from "./panels/rewrite"
import type {ValuePanel} from "./panel"

const panels: Record<string, ValuePanel> = {
  blob,
  level,
  compare,
  fleet,
  prorata,
  rewrite,
}

/** The panel a card names, from this site's six or from its product's folder. */
export const panelCalled = async (name: string): Promise<ValuePanel | undefined> => {
  if (!name.includes("/")) return panels[name]
  const [product, panel] = name.split("/")
  const own: {panels: Record<string, ValuePanel>} = await import(`./panels/${product}/index.ts`)
  return own.panels[panel!]
}
