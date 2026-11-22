import {BASE, EASE_OUT, play, still, watched} from "./motion/shared"
import type {Hook} from "../../hook_composition"

type RoomPostsHook = {el: HTMLElement; before?: Set<string>}

/**
 * A room's posts as they come: a new post fades in where it lands and nothing
 * else in the room moves, so the posts already there stay where the reader
 * has them. A room holds up to 200 posts, and moving every one of them for
 * each new post kept the page busy for most of a second. With motion reduced,
 * or as the room is drawn again when its connection comes back, a post is
 * simply there.
 */
export const RoomPosts: Hook = {
  beforeUpdate(this: RoomPostsHook) {
    this.before = new Set([...this.el.children].map(post => post.id))
  },

  updated(this: RoomPostsHook) {
    const fresh = [...this.el.children].filter(post => !this.before!.has(post.id))
    if (fresh.length > 0 && watched(this.el) && !still(this.el)) play(fresh, {opacity: {from: 0}, duration: BASE, ease: EASE_OUT})
  },
}
