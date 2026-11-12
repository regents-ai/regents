/**
 * Cloak's four, as the template's value cards gallery showed them, with its
 * panels as they are. Rewriting is this site's own violet one, the panel the
 * Overview's Cloak card shows too.
 */
import {circuit} from "./circuit"
import {cover} from "./cover"
import {rewrite} from "./rewrite"
import {sandbox} from "./sandbox"
import type {ValuePanel} from "../../panel"

export const panels: Record<string, ValuePanel> = {
  rewrite,
  circuit,
  cover,
  sandbox,
}
