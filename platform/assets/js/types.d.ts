declare module "phoenix" {
  export const Socket: unknown
}

declare module "phoenix_html"

declare module "phoenix_live_view" {
  // The exact surface this application uses from phoenix_live_view 1.2.7.
  export class LiveSocket {
    constructor(path: string, socket: unknown, options: Record<string, unknown>)
    connect(): void
    getSocket(): {connect: () => void}
  }
}

declare module "phoenix-colocated/regents" {
  export const hooks: Record<string, Record<string, (...args: unknown[]) => unknown>>
}

declare module "*.css"

interface Window {
  liveSocket: import("phoenix_live_view").LiveSocket
}
