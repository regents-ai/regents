import type {Hook} from "../../hook_composition"

/** How a time is written, as `KeyfleetWeb.Time.local/1` names it. */
export type TimeStyle = "clock" | "moment" | "stamp" | "date"

type Reader = {locale: string | undefined; timeZone: string}

type LocalTimeHook = {el: HTMLTimeElement}

const dayMs = 24 * 60 * 60 * 1000

// The reader's own calendar day of `at`, with its parts as English words.
function day(at: Date, timeZone: string) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-US", {
      timeZone,
      year: "numeric",
      month: "numeric",
      day: "numeric",
    })
      .formatToParts(at)
      .map(part => [part.type, part.value]),
  )
  const words = (month: "short" | "long") =>
    new Intl.DateTimeFormat("en-US", {timeZone, month}).format(at)

  return {
    serial: Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day)) / dayMs,
    day: parts.day,
    year: Number(parts.year),
    short: words("short"),
    long: words("long"),
  }
}

/**
 * `at` as its reader keeps time: the clock in their own time zone and
 * fashion, and today and yesterday by their own calendar. The words are the
 * page's own (`KeyfleetWeb.Time`), without the "UTC" the page writes before
 * it is live: "clock" is "20:03" today, then "Yesterday", then as "moment";
 * "moment" is "Today 20:03", "Yesterday 09:10", then "22 Sep", with the year
 * when it is not this year's; "stamp" is "20 October 2026 at 20:03"; "date"
 * is "20 Oct 2026".
 */
export function localTime(at: Date, now: Date, style: TimeStyle, {locale, timeZone}: Reader) {
  const time = new Intl.DateTimeFormat(locale, {timeZone, timeStyle: "short"}).format(at)
  const when = day(at, timeZone)
  const today = day(now, timeZone)
  const daysAgo = today.serial - when.serial

  const moment = () => {
    if (daysAgo <= 0) return `Today ${time}`
    if (daysAgo === 1) return `Yesterday ${time}`
    if (when.year === today.year) return `${when.day} ${when.short}`
    return `${when.day} ${when.short} ${when.year}`
  }

  switch (style) {
    case "clock":
      if (daysAgo <= 0) return time
      if (daysAgo === 1) return "Yesterday"
      return moment()
    case "moment":
      return moment()
    case "stamp":
      return `${when.day} ${when.long} ${when.year} at ${time}`
    case "date":
      return `${when.day} ${when.short} ${when.year}`
  }
}

function draw(hook: LocalTimeHook) {
  const at = new Date(hook.el.dateTime)
  const reader = {locale: undefined, timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone}
  const now = new Date()
  const {as, titleAs} = hook.el.dataset

  hook.el.textContent = localTime(at, now, as as TimeStyle, reader)
  if (titleAs) hook.el.title = localTime(at, now, titleAs as TimeStyle, reader)
}

/**
 * Writes a `<time>` again in its reader's own time zone once the page is
 * live, and after every change the page makes to it.
 */
export const LocalTime: Hook = {
  mounted(this: LocalTimeHook) {
    draw(this)
  },

  updated(this: LocalTimeHook) {
    draw(this)
  },
}
