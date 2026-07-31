import type {IdentityRequest} from "../auth_lazy"
import type {Hook} from "../hook_composition"

type VerifiedConnectionsHook = Hook & {
  handleEvent(event: string, callback: (payload: unknown) => void): void
  pushEvent(event: string, payload: unknown): void
  identityStateListener?: (event: Event) => void
}

export const VerifiedConnections: Hook = {
  mounted(this: VerifiedConnectionsHook) {
    this.handleEvent("verified-connections:request", payload => {
      window.dispatchEvent(
        new CustomEvent<IdentityRequest>("ash:identity-request", {
          detail: payload as IdentityRequest,
        }),
      )
    })

    this.identityStateListener = event => {
      const detail =
        event instanceof CustomEvent && typeof event.detail === "object"
          ? event.detail
          : {error: "failed"}
      this.pushEvent("refresh_verified_connections", detail)
    }
    window.addEventListener("ash:identity-state", this.identityStateListener)
  },

  destroyed(this: VerifiedConnectionsHook) {
    if (this.identityStateListener) {
      window.removeEventListener("ash:identity-state", this.identityStateListener)
    }
  },
}
