// Keyfleet's pages (`RegentsWeb.Keyfleet`): the hooks their markup names and
// what they watch on the whole document. Where the site has a hook of the same
// name that moves differently, Keyfleet's is named for Keyfleet (its list,
// its tick, its tour and its wallet buttons); the rest of the site's motion is
// shared.

import {Countdown} from "./hooks/countdown"
import {FleetPreview} from "./hooks/fleet_preview"
import {FleetTabs} from "./hooks/fleet_tabs"
import {HarbourSea} from "./hooks/harbour_sea"
import {KeyCardTurn} from "./hooks/key_card"
import {KeyCards} from "./hooks/key_cards"
import {KeyMap} from "./hooks/key_map"
import {LocalTime} from "./hooks/local_time"
import {ModalDialog, watchPresses} from "./hooks/modal_dialog"
import {MotionList, MotionStamp, MotionTick} from "./hooks/motion/moments"
import {watchInput} from "./hooks/motion/shared"
import {OnchainSteps} from "./hooks/onchain_steps"
import {RoomPosts} from "./hooks/room_posts"
import {RoomThread} from "./hooks/room_thread"
import {ScheduleCard} from "./hooks/schedule_card"
import {ScrollRow} from "./hooks/scroll_row"
import {Tour} from "./hooks/tour"

export const keyfleetHooks = {
  Countdown,
  FleetPreview,
  FleetTabs,
  HarbourSea,
  KeyCards,
  KeyCardTurn,
  KeyfleetMotionList: MotionList,
  KeyfleetMotionTick: MotionTick,
  KeyfleetOnchainSteps: OnchainSteps,
  KeyfleetTour: Tour,
  KeyMap,
  LocalTime,
  ModalDialog,
  MotionStamp,
  RoomPosts,
  RoomThread,
  ScheduleCard,
  ScrollRow,
}

// A room opened from its fleet's hall takes the keyboard to its name, so a
// screen reader says which room it is. The name takes it where it stands:
// the room itself opens at its newest post (hooks/room_thread.ts). Any other
// step within the page leaves the keyboard where it is.
let shownRoom = new URLSearchParams(window.location.search).get("room")

function focusRoomName(event: Event) {
  const room = new URLSearchParams(window.location.search).get("room")
  const opened = room !== null && room !== shownRoom
  shownRoom = room
  if (!opened || (event as CustomEvent<{kind?: string}>).detail?.kind !== "patch") return
  document.getElementById("rooms-thread-title")?.focus({preventScroll: true})
}

export function installKeyfleet() {
  watchInput(document)
  watchPresses(document)
  window.addEventListener("phx:page-loading-stop", focusRoomName)
}
