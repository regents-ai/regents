/**
 * Autolaunch's six, as autolaunch.sh shows them on its home page under
 * "Principles" (`AutolaunchWeb.HomeLive`); the panels are its own, as they are.
 */
import {address} from "./address"
import {blocks} from "./blocks"
import {clearing} from "./clearing"
import {handoff} from "./handoff"
import {signature} from "./signature"
import {vault} from "./vault"
import type {ValuePanel} from "../../panel"

export const panels: Record<string, ValuePanel> = {
  clearing,
  vault,
  address,
  signature,
  handoff,
  blocks,
}
