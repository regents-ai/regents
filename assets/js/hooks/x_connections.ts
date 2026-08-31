import {browserCsrfToken} from "../auth_lazy"
import type {Hook} from "../hook_composition"

type XRole = "profile" | "company"
type StartResponse = {url?: unknown; role?: unknown; generation?: unknown; error?: unknown}
type CallbackMessage = {
  source?: unknown
  status?: unknown
  role?: unknown
  generation?: unknown
}
type StartAttempt = {
  role: XRole
  controller: AbortController
  timeout: number
}

type XConnectionsHook = Hook & {
  el: HTMLElement
  pushEvent(event: string, payload: unknown): void
  activeStart?: StartAttempt
  cancelActiveStart?: (selectedRole?: XRole) => void
  activePopup?: Window | null
  activeRole?: XRole
  activeGeneration?: string
  popupPoll?: number
  clickListener?: (event: Event) => void
  messageListener?: (event: MessageEvent) => void
}

const startTimeoutMs = 10_000

function role(value: string | undefined): XRole | null {
  return value === "profile" || value === "company" ? value : null
}

function status(root: HTMLElement, message: string): void {
  const target = root.querySelector<HTMLElement>("[data-x-connection-status]")
  if (target) target.textContent = message
}

async function json(response: Response): Promise<StartResponse> {
  try {
    return (await response.json()) as StartResponse
  } catch {
    return {}
  }
}

async function mutate(
  path: string,
  method: "POST" | "DELETE",
  signal?: AbortSignal,
): Promise<Response> {
  return fetch(path, {
    method,
    credentials: "same-origin",
    headers: {"x-csrf-token": browserCsrfToken(), accept: "application/json"},
    ...(signal ? {signal} : {}),
  })
}

export const XConnections: Hook = {
  mounted(this: XConnectionsHook) {
    const reset = () => {
      if (this.popupPoll) window.clearInterval(this.popupPoll)
      this.popupPoll = undefined
      this.activePopup = null
      this.activeRole = undefined
      this.activeGeneration = undefined
    }

    const releaseStart = (attempt: StartAttempt) => {
      window.clearTimeout(attempt.timeout)
      if (this.activeStart === attempt) this.activeStart = undefined
    }

    const cancelStart = (selectedRole?: XRole) => {
      const attempt = this.activeStart
      if (!attempt || (selectedRole && attempt.role !== selectedRole)) return

      attempt.controller.abort()
      releaseStart(attempt)
    }

    this.cancelActiveStart = cancelStart

    const start = (selectedRole: XRole) => {
      cancelStart()
      this.activePopup?.close()
      reset()
      const popup = window.open("", "regents-x-oauth", "popup,width=620,height=720")
      if (!popup) {
        status(this.el, "Allow popups to connect X.")
        return
      }

      this.activePopup = popup
      this.activeRole = selectedRole
      this.activeGeneration = undefined
      popup.document.title = "Connecting X"
      status(this.el, `Opening ${selectedRole} X connection…`)
      this.popupPoll = window.setInterval(() => {
        if (this.activePopup !== popup || !popup.closed) return
        cancelStart(selectedRole)
        reset()
        status(this.el, "X connection was not completed.")
      }, 250)

      const attempt: StartAttempt = {
        role: selectedRole,
        controller: new AbortController(),
        timeout: 0,
      }

      attempt.timeout = window.setTimeout(() => {
        if (this.activeStart !== attempt) return

        attempt.controller.abort()
        releaseStart(attempt)
        popup.close()

        if (this.activePopup === popup) {
          reset()
          status(this.el, "X connection could not start. Try again.")
        }
      }, startTimeoutMs)

      this.activeStart = attempt

      void (async () => {
        try {
          const response = await mutate(
            `/auth/x/connections/${selectedRole}`,
            "POST",
            attempt.controller.signal,
          )
          const body = await json(response)
          if (
            !response.ok ||
            body.role !== selectedRole ||
            typeof body.url !== "string" ||
            typeof body.generation !== "string"
          ) {
            throw new Error("start refused")
          }

          if (this.activePopup !== popup || popup.closed || attempt.controller.signal.aborted) return
          this.activeGeneration = body.generation
          popup.location.replace(body.url)
        } catch {
          if (!attempt.controller.signal.aborted) popup.close()

          if (this.activePopup === popup && !attempt.controller.signal.aborted) {
            reset()
            status(this.el, "X connection could not start. Try again.")
          }
        } finally {
          releaseStart(attempt)
        }
      })()
    }

    const disconnect = (selectedRole: XRole) => {
      cancelStart(selectedRole)

      if (this.activeRole === selectedRole) {
        this.activePopup?.close()
        reset()
      }

      status(this.el, `Disconnecting ${selectedRole} X…`)

      void (async () => {
        try {
          const response = await mutate(`/auth/x/connections/${selectedRole}`, "DELETE")
          if (!response.ok) throw new Error("disconnect refused")
          status(this.el, "X account disconnected.")
          this.pushEvent("refresh_x_connections", {role: selectedRole, status: "disconnected"})
        } catch {
          status(this.el, "X account could not be disconnected. Try again.")
        }
      })()
    }

    this.clickListener = event => {
      const target = event.target instanceof Element ? event.target : null
      const connectRole = role(target?.closest<HTMLElement>("[data-x-connect-role]")?.dataset.xConnectRole)
      const disconnectRole = role(
        target?.closest<HTMLElement>("[data-x-disconnect-role]")?.dataset.xDisconnectRole,
      )
      if (connectRole) void start(connectRole)
      if (disconnectRole) void disconnect(disconnectRole)
    }

    this.messageListener = event => {
      const expectedOrigin = this.el.dataset.xOauthOrigin
      const message = event.data as CallbackMessage
      if (
        event.origin !== expectedOrigin ||
        event.source !== this.activePopup ||
        message?.source !== "ash-x-oauth" ||
        message.role !== this.activeRole ||
        message.generation !== this.activeGeneration
      ) {
        return
      }

      const selectedRole = this.activeRole
      this.activePopup?.close()
      reset()
      if (message.status === "connected") {
        status(this.el, "X account connected.")
        this.pushEvent("refresh_x_connections", {role: selectedRole, status: "connected"})
      } else {
        status(this.el, "X connection was not completed.")
      }
    }

    this.el.addEventListener("click", this.clickListener)
    window.addEventListener("message", this.messageListener)
  },

  destroyed(this: XConnectionsHook) {
    this.cancelActiveStart?.()
    this.activePopup?.close()
    if (this.popupPoll) window.clearInterval(this.popupPoll)
    if (this.clickListener) this.el.removeEventListener("click", this.clickListener)
    if (this.messageListener) window.removeEventListener("message", this.messageListener)
  },
}
