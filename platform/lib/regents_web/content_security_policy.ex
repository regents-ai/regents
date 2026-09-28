defmodule RegentsWeb.ContentSecurityPolicy do
  @moduledoc """
  The content security policies the site's pages are served under.

  `reading/0` is the strict baseline: scripts, styles, images, fonts and video
  come from this site, requests and the live connection go back to it, no page
  frames another site or is framed itself, and forms submit only here.

  `sign_in/0` is the baseline plus what Privy's wallet sign-in loads, from
  Privy's published policy: Privy's API, frame and wallet RPC, Cloudflare
  Turnstile, WalletConnect's relays, verify frames, wallet list, logos, RPC and
  event reporting, Coinbase Wallet's relay, and the Telegram sign-in this Privy
  app offers, whose script comes from both Privy and Telegram. Privy's sign-in window writes its own style elements, so only this
  profile allows them. Its pages also show pictures from other sites: an ENS
  avatar is whatever https address the name's holder set, so images may come
  from any https host.

  `showcase/0` is `sign_in/0` for the local showcase, which frames its own
  preview page.

  A page that loads anything else adds each origin to the one directive and the
  one profile that needs it.
  """

  # The development code reloader runs in a frame from this site.
  @own_frames if Application.compile_env(:regents, [RegentsWeb.Endpoint, :code_reloader]),
                do: ["'self'"],
                else: []

  @baseline [
    {"default-src", ["'none'"]},
    {"script-src", ["'self'"]},
    {"style-src", ["'self'"]},
    # Style attributes only, never style elements: the shared ratio card sizes
    # its fill with one, and Anime.js text splitting clips each word with one.
    {"style-src-attr", ["'unsafe-inline'"]},
    {"img-src", ["'self'", "data:"]},
    {"font-src", ["'self'"]},
    # Redeem's artwork video is served from this site.
    {"media-src", ["'self'"]},
    {"connect-src", ["'self'"]},
    {"frame-src", @own_frames},
    {"base-uri", ["'none'"]},
    {"form-action", ["'self'"]},
    {"frame-ancestors", ["'none'"]}
  ]

  @sign_in %{
    "script-src" => [
      "https://auth.privy.io",
      "https://challenges.cloudflare.com",
      "https://telegram.org"
    ],
    "style-src" => ["'unsafe-inline'"],
    "img-src" => ["blob:", "https:"],
    "frame-src" => [
      "https://auth.privy.io",
      "https://verify.walletconnect.com",
      "https://verify.walletconnect.org",
      "https://challenges.cloudflare.com",
      "https://oauth.telegram.org"
    ],
    "connect-src" => [
      "https://auth.privy.io",
      "https://*.rpc.privy.systems",
      "wss://relay.walletconnect.com",
      "wss://relay.walletconnect.org",
      "https://verify.walletconnect.org",
      "https://explorer-api.walletconnect.com",
      "https://rpc.walletconnect.org",
      "https://pulse.walletconnect.org",
      "wss://www.walletlink.org"
    ]
  }

  @doc "The strict baseline, for pages that never start sign-in."
  def reading, do: render(@baseline)

  @doc "The baseline plus Privy wallet sign-in, for pages that can sign someone in."
  def sign_in, do: @baseline |> add(@sign_in) |> render()

  @doc "Sign-in plus framing its own pages, for the local showcase's preview."
  def showcase do
    @baseline
    |> add(@sign_in)
    |> add(%{"frame-src" => ["'self'"]})
    |> List.keyreplace("frame-ancestors", 0, {"frame-ancestors", ["'self'"]})
    |> render()
  end

  defp add(directives, additions) do
    Enum.map(directives, fn {directive, sources} ->
      {directive, Enum.uniq(sources ++ Map.get(additions, directive, []))}
    end)
  end

  defp render(directives) do
    directives
    |> Enum.reject(fn {_directive, sources} -> sources == [] end)
    |> Enum.map_join("; ", fn {directive, sources} -> Enum.join([directive | sources], " ") end)
  end
end
