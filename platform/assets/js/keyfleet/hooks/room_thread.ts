import type {Hook} from "../../hook_composition"

/**
 * A room's posts, which open at the newest one, with the box to write in under
 * it, and stay there while the reader is there. The rule, all of it:
 *
 * The end is the bottom of the foot under the posts, which holds a refusal and
 * the box to write in, where the foot is drawn: never how far the room can
 * scroll. The end is on screen when it lies in the part of the room's column
 * the window shows: the column's own box on a wide screen, where the room
 * scrolls by itself, and the window on a narrow one, where the page scrolls.
 *
 * Whenever the posts, the foot or the room change size, as a post arrives or
 * goes, a picture loads, the window resizes or a refusal shows, and whenever
 * the server draws the posts again, which can swap the oldest post for a new
 * one of the same height and change no size at all, the room follows to the
 * end if the end was on screen before the change, at the place the reader
 * left the room, or is on screen now. Where the reader left it is read two
 * ways, and either one that puts the end on screen will do. One is the first
 * post on screen after the last change, or the foot when no post is: the
 * browser keeps that post in place when posts above it come or go, so how far
 * it has moved since is how far the reader scrolled. The browser does not do
 * that for every change: a post gains the space and line under it once a
 * newer post lands below it, and when that post is the first on screen, or
 * just above it, the browser can let the first post move. So the other is how
 * far the room's posts have scrolled since, in the room or with the page,
 * which is how far the reader scrolled whenever the browser kept nothing in
 * place. Nothing listens to scrolling: a reader who scrolled up to read is
 * left there.
 *
 * Following puts the foot's bottom at the column's bottom, with the column's
 * own spacing under it, and scrolls the page only when the room's own bottom
 * is off the screen. Opening the room, which mounts this element afresh, the
 * reader's own post and a connection that comes back take the room to the end.
 */

// How near the end still counts as on screen: what zoom loses to rounding.
const NEAR = 2

// The part of the room's column the window shows, as drawn in the window.
type Shown = {top: number; bottom: number}

// The room as the last change left it: the first post on screen, or the foot,
// and its top; how far the posts had scrolled; the foot's bottom; and the
// part of the column then shown.
type Mark = {first: Element; top: number; scrolled: number; end: number; shown: Shown}

type RoomThreadHook = {
  el: HTMLElement
  room?: HTMLElement
  mark?: Mark
  follow?: () => void
  keep?: () => void
  watch?: ResizeObserver
}

function shown(room: HTMLElement): Shown {
  const top = room.getBoundingClientRect().top + room.clientTop
  return {top: Math.max(top, 0), bottom: Math.min(top + room.clientHeight, innerHeight)}
}

const onScreen = (y: number, {top, bottom}: Shown) => y > top && y <= bottom + NEAR

// How far the room's posts have scrolled under the window: in the room's own
// column on a wide screen, with the page on a narrow one.
const scrolled = (room: HTMLElement) => room.scrollTop - room.getBoundingClientRect().top

function mark(room: HTMLElement, foot: HTMLElement): Mark {
  const now = shown(room)
  const posts = [...room.querySelectorAll("[data-post]")]
  const first = posts.find(post => post.getBoundingClientRect().bottom > now.top) ?? foot
  return {
    first,
    top: first.getBoundingClientRect().top,
    scrolled: scrolled(room),
    end: foot.getBoundingClientRect().bottom,
    shown: now,
  }
}

function wasAtEnd(room: HTMLElement, {first, top, scrolled: before, end, shown}: Mark) {
  const byPost = first.isConnected && onScreen(end + first.getBoundingClientRect().top - top, shown)
  return byPost || onScreen(end - scrolled(room) + before, shown)
}

function toEnd(room: HTMLElement, foot: HTMLElement) {
  const column = room.getBoundingClientRect().top + room.clientTop + room.clientHeight
  room.scrollTop += foot.getBoundingClientRect().bottom + parseFloat(getComputedStyle(room).paddingBottom) - column
  const {bottom} = room.getBoundingClientRect()
  if (bottom > innerHeight || bottom < 0) room.scrollIntoView({block: "end", behavior: "instant"})
}

export const RoomThread: Hook = {
  mounted(this: RoomThreadHook) {
    const room = this.el.closest<HTMLElement>(".rooms-thread")!
    const foot = room.querySelector<HTMLElement>(".rooms-foot")!
    const follow = () => {
      toEnd(room, foot)
      this.mark = mark(room, foot)
    }
    const keep = () => {
      if (wasAtEnd(room, this.mark!) || onScreen(foot.getBoundingClientRect().bottom, shown(room))) toEnd(room, foot)
      this.mark = mark(room, foot)
    }
    this.room = room
    this.follow = follow
    this.keep = keep
    this.watch = new ResizeObserver(keep)
    for (const box of [this.el, foot, room]) this.watch.observe(box)
    room.addEventListener("submit", follow)
    follow()
  },

  updated(this: RoomThreadHook) {
    this.keep!()
  },

  reconnected(this: RoomThreadHook) {
    this.follow!()
  },

  destroyed(this: RoomThreadHook) {
    this.watch?.disconnect()
    this.room?.removeEventListener("submit", this.follow!)
  },
}
