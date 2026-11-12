/**
 * Keyfleet's six, as keyfleet.ai shows them on its homepage under "Overview"
 * (`KeyfleetWeb.HomeLive`); the panels are its own, as they are. Its first,
 * `fleet`, is this site's own Keyfleet panel, so its card names that one.
 */
import {ballot} from "./ballot"
import {board} from "./board"
import {ledger} from "./ledger"
import {link} from "./link"
import {rooms} from "./rooms"
import type {ValuePanel} from "../../panel"

export const panels: Record<string, ValuePanel> = {
  rooms,
  board,
  link,
  ballot,
  ledger,
}
