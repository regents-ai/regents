/**
 * Every value card's panel, by the name its card carries in `data-value-card`.
 * This site's own five come with the renderer. A product page shows that
 * product's own cards, kept in `panels/<product>/` and listed in its `index.ts`:
 * such a card names its panel `<product>/<name>`, and the product's panels
 * arrive together the first time a page shows one.
 */
import {blob} from "./panels/blob"
import {compare} from "./panels/compare"
import {fleet} from "./panels/fleet"
import {level} from "./panels/level"
import {prorata} from "./panels/prorata"
import type {ValuePanel} from "./panel"

const panels: Record<string, ValuePanel> = {
  blob,
  level,
  compare,
  fleet,
  prorata,
}

/** The panel a card names, from this site's six or from its product's folder. */
export const panelCalled = async (name: string): Promise<ValuePanel | undefined> => {
  if (!name.includes("/")) return panels[name]
  const [product, panel] = name.split("/")
  const own: {panels: Record<string, ValuePanel>} = await import(`./panels/${product}/index.ts`)
  return own.panels[panel!]
}
