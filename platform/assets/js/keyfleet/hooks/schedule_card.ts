import type {Hook} from "../../hook_composition"

type ScheduleCardHook = {
  el: HTMLElement
  pushEvent(event: string, payload: object): void
}

/**
 * Schedule on a fleet's page (`KeyfleetWeb.Components.ScheduleCard`), which
 * its person may put away for that fleet. Only this browser remembers it, in
 * a cookie the server reads as each page is requested
 * (`KeyfleetWeb.Live.Session.render_context/1`), so the next page is drawn
 * without it. Putting it away here, or finding it put away since the page
 * was requested, hides it at once and tells the page what the cookie says
 * now, which takes it away.
 */
const cookieName = "keyfleet_schedule"
const maxAge = 60 * 60 * 24 * 365
/** A fleet's id as the catalog writes it, and how many the cookie keeps, the latest. */
const fleetId = /^[a-z0-9_]+$/
const kept = 16

/** The fleets whose Schedule this browser put away, as their ids joined by dots. */
function putAway(): string {
  const prefix = `${cookieName}=`
  return (
    document.cookie
      .split("; ")
      .find(cookie => cookie.startsWith(prefix))
      ?.slice(prefix.length) ?? ""
  )
}

function fleetsPutAway(): string[] {
  return putAway().split(".").filter(Boolean)
}

function keepAway(fleet: string) {
  const fleets = [...new Set([...fleetsPutAway().filter(id => id !== fleet), fleet])]
    .filter(id => fleetId.test(id))
    .slice(-kept)
    .join(".")
  const secure = window.location.protocol === "https:" ? "; Secure" : ""
  document.cookie = `${cookieName}=${fleets}; Path=/; Max-Age=${maxAge}; SameSite=Lax${secure}`
}

function goAway(hook: ScheduleCardHook) {
  hook.el.hidden = true
  hook.pushEvent("schedule_put_away", {put_away: putAway()})
}

export const ScheduleCard: Hook = {
  mounted(this: ScheduleCardHook) {
    const fleet = this.el.dataset.fleet!
    if (fleetsPutAway().includes(fleet)) goAway(this)

    this.el.querySelector("[data-dismiss]")?.addEventListener("click", () => {
      keepAway(fleet)
      goAway(this)
    })
  },
}
