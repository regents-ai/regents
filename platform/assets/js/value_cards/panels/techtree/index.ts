/**
 * Techtree's six, as techtree.sh shows them on its home page under "Products"
 * (`TechtreeWeb.HomeLive`); the panels are its own, as they are.
 */
import {check} from "./check"
import {compare} from "./compare"
import {repo} from "./repo"
import {train} from "./train"
import {wallet} from "./wallet"
import {watch} from "./watch"
import type {ValuePanel} from "../../panel"

export const panels: Record<string, ValuePanel> = {
  compare,
  wallet,
  train,
  check,
  repo,
  watch,
}
