/**
 * Patchbay's six, as patchbay.help shows them on its home page
 * (`PatchbayWeb.Forum.BoardHTML.home_cards/0`); the panels are its own, as they are.
 */
import {ask} from "./ask"
import {bench} from "./bench"
import {connect} from "./connect"
import {fixes} from "./fixes"
import {pair} from "./pair"
import {sites} from "./sites"
import type {ValuePanel} from "../../panel"

export const panels: Record<string, ValuePanel> = {
  ask,
  sites,
  fixes,
  pair,
  bench,
  connect,
}
