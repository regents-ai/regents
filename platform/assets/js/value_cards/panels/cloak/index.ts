/**
 * Cloak's one card panel: Rewriting, this site's own violet one, which the
 * Overview's Cloak card shows.
 */
import {rewrite} from "./rewrite"
import type {ValuePanel} from "../../panel"

export const panels: Record<string, ValuePanel> = {
  rewrite,
}
