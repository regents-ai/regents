export type PrivyPair = {accessToken: string; identityToken: string}

export type PrivySignInFailure =
  | "flow_closed"
  | "invalid_message"
  | "provider_error"
  | "request_timeout"
  | "session_exchange"
  | "unable_to_sign"

export function readPrivyPair(sources: {
  getIdentityToken: () => Promise<string | null>
  getAccessToken: () => Promise<string | null>
  requireCurrent?: () => void
}): Promise<PrivyPair>

export function privyPairHeaders(pair: PrivyPair): {authorization: string; "privy-id-token": string}

export function privyLoginFailure(error: unknown): Exclude<PrivySignInFailure, "session_exchange">

export type PrivySignIn = {
  signIn: () => Promise<void>
  signOut: () => Promise<void>
}

export function startPrivySignIn(options: {
  appId: string
  sessionPath: string
  csrfToken: string
  session?: {id: string; current: boolean} | null
  config?: Record<string, unknown>
  onSignedIn?: () => void
  onRenewed?: () => void
  onFailure?: (failure: PrivySignInFailure) => void
}): Promise<PrivySignIn>
