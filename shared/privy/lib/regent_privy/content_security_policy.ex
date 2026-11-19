defmodule RegentPrivy.ContentSecurityPolicy do
  @moduledoc """
  The sources a page's content security policy adds so Privy's sign-in can run,
  from Privy's published policy and the bundled Privy and WalletConnect code.
  An app adds each list to the one directive it names in its own policy, on the
  pages that can sign someone in, and nothing else. Privy's sign-in window writes
  its own style elements, so `style-src` takes `'unsafe-inline'`. The only
  wildcard is Privy's own `*.rpc.privy.systems`.
  """

  @sign_in %{
    "script-src" => ["https://challenges.cloudflare.com"],
    "style-src" => ["'unsafe-inline'"],
    "img-src" => ["blob:", "https://explorer-api.walletconnect.com"],
    "frame-src" => [
      "https://auth.privy.io",
      "https://verify.walletconnect.com",
      "https://verify.walletconnect.org",
      "https://challenges.cloudflare.com"
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

  @doc "Privy's sign-in sources, by directive."
  @spec sign_in() :: %{String.t() => [String.t()]}
  def sign_in, do: @sign_in
end
