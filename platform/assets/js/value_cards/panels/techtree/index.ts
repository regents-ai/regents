/**
 * The pictures on the Techtree page's six cards: techtree.sh's five services and
 * its Wallet Bench (`RegentsWeb.ProductLive`), each in Techtree's own colours.
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
