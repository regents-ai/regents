import {sign} from "node:crypto"
import type {Page} from "@playwright/test"

// Privy's own servers, answered on this machine so the real Privy library runs
// on the page. The person is the one `Regents.TestPrivyVerifier` signs in with
// "valid", and every token is signed with the run's test key, which the test
// server checks (playwright.config.ts), so the tokens Privy hands the page are
// the ones the server accepts.
export const privyAppId = "browser-test-privy-app-id"
export const privySubject = "did:privy:verified"
const wallet = "0x1111111111111111111111111111111111111111"

const base64url = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url")

function signed(claims: Record<string, unknown>): string {
  const body = `${base64url({alg: "ES256", typ: "JWT"})}.${base64url(claims)}`
  const signature = sign("sha256", Buffer.from(body), {
    key: process.env.REGENTS_BROWSER_PRIVY_SIGNING_KEY!,
    dsaEncoding: "ieee-p1363",
  })
  return `${body}.${signature.toString("base64url")}`
}

const now = () => Math.floor(Date.now() / 1000)

const claims = () => ({iss: "privy.io", aud: privyAppId, sub: privySubject, iat: now() - 1, exp: now() + 3600})

export const accessToken = () => signed({...claims(), sid: "browser-privy-session"})

export const identityToken = () =>
  signed({
    ...claims(),
    linked_accounts: JSON.stringify([{type: "wallet", chain_type: "ethereum", address: wallet, lv: 1}]),
  })

const user = () => ({
  id: privySubject,
  created_at: now() - 86_400,
  linked_accounts: [{
    type: "wallet", address: wallet, chain_type: "ethereum", chain_id: "eip155:8453",
    wallet_client: "unknown", wallet_client_type: "metamask", connector_type: "injected",
    verified_at: now() - 86_400, first_verified_at: now() - 86_400, latest_verified_at: now() - 86_400,
  }],
  mfa_methods: [],
  has_accepted_terms: true,
  is_guest: false,
})

const appConfig = {
  id: privyAppId, name: "Regents", legal_name: null, logo_url: null, icon_url: null, theme: "light",
  accent_color: null, terms_and_conditions_url: null, privacy_policy_url: null,
  require_users_accept_terms: false, show_wallet_login_first: true,
  allowlist_config: {error_title: null, error_detail: null, cta_text: null, cta_link: null},
  wallet_auth: true, solana_wallet_auth: false, email_auth: false, sms_auth: false, whatsapp_enabled: false,
  google_oauth: false, twitter_oauth: false, discord_oauth: false, github_oauth: false,
  linkedin_oauth: false, apple_oauth: false, spotify_oauth: false, instagram_oauth: false,
  tiktok_oauth: false, line_oauth: false, twitch_oauth: false, telegram_auth: false,
  telegram_auth_config: null, farcaster_auth: false, passkey_auth: false,
  passkeys_for_signup_enabled: false, guest_auth: false, custom_oauth_providers: [],
  disable_plus_emails: false, enforce_wallet_uis: false, legacy_wallet_ui_config: false,
  embedded_wallet_config: {
    create_on_login: "all-users", ethereum: {create_on_login: "all-users"}, solana: {create_on_login: "off"},
    require_user_owned_recovery_on_create: false, user_owned_recovery_options: ["user-passcode"],
    mode: "user-controlled-server-wallets-only",
  },
  smart_wallet_config: {enabled: false}, funding_config: null, mfa_methods: [],
  enabled_captcha_provider: null, captcha_site_key: null, wallet_connect_cloud_project_id: null,
  max_linked_wallets_per_user: null, custom_api_url: null,
}

// The page starts signed in to Privy, as a returning person's browser is: Privy
// restores the session from what it stored, refreshes it, and stores the new
// tokens, which is when it tells the page a token was granted. Every
// identity-token read is a request to Privy, and Privy, like any service with a
// rate limit, refuses one that follows another within a second.
export async function installPrivyService(page: Page): Promise<void> {
  let lastAnswered = 0

  await page.addInitScript(
    ([access, identity]) => {
      if (sessionStorage.getItem("privy-service-seeded")) return
      sessionStorage.setItem("privy-service-seeded", "true")
      localStorage.setItem("privy:token", JSON.stringify(access))
      localStorage.setItem("privy:pat", JSON.stringify(access))
      localStorage.setItem("privy:refresh_token", JSON.stringify("browser-privy-refresh"))
      localStorage.setItem("privy:id_token", JSON.stringify(identity))
    },
    [accessToken(), identityToken()],
  )

  await page.route("https://auth.privy.io/**", route => {
    const {pathname} = new URL(route.request().url())
    const json = (status: number, body: unknown) =>
      route.fulfill({status, contentType: "application/json", body: JSON.stringify(body)})

    if (pathname === `/api/v1/apps/${privyAppId}`) return json(200, appConfig)
    if (pathname === "/api/v1/sessions") {
      return json(200, {
        user: user(), token: accessToken(), privy_access_token: accessToken(),
        refresh_token: "browser-privy-refresh", identity_token: identityToken(), session_update_action: "set",
      })
    }
    if (pathname === "/api/v1/users/me") {
      if (Date.now() - lastAnswered < 1000) return json(429, {error: "Too many requests"})
      lastAnswered = Date.now()
      return json(200, {user: user(), identity_token: identityToken()})
    }
    if (pathname === `/apps/${privyAppId}/embedded-wallets`) {
      return route.fulfill({contentType: "text/html", body: "<!doctype html><title>Wallets</title>"})
    }
    return json(200, {})
  })
}
