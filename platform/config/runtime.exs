import Config

require Logger

config :regents, :privy,
  app_id: System.get_env("PRIVY_APP_ID"),
  verification_key: System.get_env("PRIVY_VERIFICATION_KEY")

# Without its Privy settings a local server answers every page while nobody can
# sign in, so it refuses to start. A worktree holds no settings files of its own.
# Other mix tasks, such as migrations and code generation, run without them.
if config_env() == :dev and Phoenix.Endpoint.server?(:regents, RegentsWeb.Endpoint) do
  for name <- ~w(PRIVY_APP_ID PRIVY_VERIFICATION_KEY), System.get_env(name, "") == "" do
    raise """
    #{name} is not set, so nobody could sign in. Start the site with its settings loaded:
    direnv exec <main checkout>/platform mix phx.server
    """
  end
end

config :regents, :opensea_api_key, System.get_env("OPENSEA_API_KEY")

config :regent_sprites, token: System.get_env("SPRITES_TOKEN")

# The sign-in service asks the site at its own address whether an agent is paired
# here before it gives the agent a hello card, and its token names that address
# (RegentAgents.HelloCard): https://PHX_HOST in production, the endpoint's own
# address elsewhere.
site_url =
  if config_env() == :prod do
    case String.trim(System.get_env("PHX_HOST", "")) do
      "" -> nil
      host -> "https://" <> host
    end
  else
    url = Application.fetch_env!(:regents, RegentsWeb.Endpoint)[:url]
    URI.to_string(%URI{scheme: url[:scheme] || "http", host: url[:host], port: url[:port]})
  end

siwa_url =
  case System.get_env("SIWA_SERVER_URL") do
    value when is_binary(value) and value != "" -> value
    _unset -> if config_env() == :dev, do: "https://siwa.regents.sh", else: nil
  end

siwa_audience =
  case System.get_env("SIWA_AUDIENCE") do
    value when is_binary(value) and value != "" -> value
    _unset -> if config_env() == :dev, do: "regents.sh", else: nil
  end

config :regent_agents, :siwa,
  url: siwa_url,
  audience: siwa_audience,
  origin: site_url

if site_url, do: config(:regents, :site_origin, site_url)

# The reader key for each paired agent's activity across the Regent sites.
config :regent_agents, activity_read_token: System.get_env("SIWA_ACTIVITY_READ_TOKEN")

# Production must say out loud whether the product surfaces are open. Anything
# but "on" keeps them closed, so a typo closes rather than opens.
app_surfaces_setting =
  case {config_env(), System.get_env("REGENTS_APP_SURFACES")} do
    {:prod, nil} ->
      raise ~s(REGENTS_APP_SURFACES must be set to "on" or "off")

    {_env, nil} ->
      "on"

    {_env, setting} ->
      setting
  end

app_surfaces? = app_surfaces_setting == "on"

config :regents, :app_surfaces, app_surfaces?

Logger.info("App surfaces #{if app_surfaces?, do: "enabled", else: "disabled"}")

# The signed wallet's ENS name and picture are read from Ethereum mainnet. Only
# the host is logged, because provider URLs carry the API key.
ethereum_read_rpc_url = String.trim(System.get_env("ETHEREUM_READ_RPC_URL", ""))

if ethereum_read_rpc_url != "" do
  config :regents, :ethereum_read_rpc_url, ethereum_read_rpc_url

  Logger.info("Ethereum read endpoint host #{URI.parse(ethereum_read_rpc_url).host}")
end

# Techtree's Book Call button's booking page
# (RegentsWeb.Techtree.Components.BookCall): in Techtree's header and on every
# Techtree page that offers a call. Unset, no page shows the button; set, it is
# an https address or the boot stops.
book_call =
  case System.get_env("TECHTREE_BOOK_CALL_URL") do
    nil -> nil
    "https://" <> _rest = address -> address
    _other -> raise "TECHTREE_BOOK_CALL_URL must be an https address"
  end

config :regents, :techtree_book_call, book_call

# Techtree's catalog channel, overridable at boot. It belongs here rather than
# beside the default in `config.exs`, because that file is evaluated when the
# project is compiled: an environment variable read there is read once, at build
# time, and a later value is silently ignored.
#
# The staged publication rehearsal is why it exists. The release candidate
# publishes the stable channel while development is the default, and rehearsing
# a release should not mean editing a committed default for the occasion.
if channel = System.get_env("TECHTREE_CATALOG_CHANNEL") do
  config :regents, Regents.Techtree.Catalog,
    catalog_root: {:priv, "techtree/catalog"},
    channel: channel
end

# Techtree's catalog serving. `TECHTREE_CATALOG_ROOT` points at a generated
# bundle outside the release; without it the bundle shipped in
# `priv/techtree/catalog` is used. `TECHTREE_BOOTSTRAP_CHANNEL` selects the
# release channel that is imported and served; unset, it stays on the
# compile-time default in `config/config.exs`, which is `development`. Every
# carried snapshot declares `stable`, the channel Techtree's live site serves,
# so a site that serves the catalog names it here. No model-provider credential
# is read here.
config :regents,
       Regents.Techtree.Catalog,
       Enum.reject(
         [
           catalog_root: System.get_env("TECHTREE_CATALOG_ROOT"),
           channel: System.get_env("TECHTREE_BOOTSTRAP_CHANNEL")
         ],
         fn {_key, value} -> is_nil(value) end
       )

if signing_key = System.get_env("TECHTREE_NETWORK_SIGNING_KEY") do
  config :regents, Regents.Techtree.Network.Key, private_key: signing_key
end

if System.get_env("WALLETBENCH_BUCKET_NAME") do
  config :regents, Regents.Techtree.WalletBench.Evidence,
    endpoint: System.get_env("WALLETBENCH_AWS_ENDPOINT_URL_S3"),
    bucket: System.get_env("WALLETBENCH_BUCKET_NAME"),
    region: System.get_env("WALLETBENCH_AWS_REGION"),
    access_key_id: System.get_env("WALLETBENCH_AWS_ACCESS_KEY_ID"),
    secret_access_key: System.get_env("WALLETBENCH_AWS_SECRET_ACCESS_KEY")
end

# Autolaunch's deployment descriptions: for each network, the path of the file
# naming its contracts. Production reads Base's and Base Stocks' from the files
# the release ships (`priv/autolaunch/deployment`), under the label autolaunch.sh
# keeps its rows by; a file that is missing or malformed stops the start
# (`Regents.Autolaunch.Supervisor`). Elsewhere each is optional and named by its
# variable, as a local lab names its own; an unset or blank variable leaves its
# setting out. The Base description needs its label beside it, and the Base
# Stocks description extends the Base one, so it needs the Base description.
{base_deployment, base_deployment_id, base_stocks_deployment} =
  if config_env() == :prod do
    {Application.app_dir(:regents, "priv/autolaunch/deployment/base.json"), "base-mainnet",
     Application.app_dir(:regents, "priv/autolaunch/deployment/base-stocks.json")}
  else
    env_base = String.trim(System.get_env("AUTOLAUNCH_BASE_DEPLOYMENT", ""))
    env_base_id = String.trim(System.get_env("AUTOLAUNCH_BASE_DEPLOYMENT_ID", ""))
    env_stocks = String.trim(System.get_env("AUTOLAUNCH_BASE_STOCKS_DEPLOYMENT", ""))

    if config_env() == :dev and env_base == "" and env_stocks == "" do
      {Application.app_dir(:regents, "priv/autolaunch/deployment/base.json"), "base-mainnet",
       Application.app_dir(:regents, "priv/autolaunch/deployment/base-stocks.json")}
    else
      {env_base, env_base_id, env_stocks}
    end
  end

robinhood_deployment = String.trim(System.get_env("AUTOLAUNCH_ROBINHOOD_DEPLOYMENT", ""))

if base_deployment != "" do
  if base_deployment_id == "" do
    raise "AUTOLAUNCH_BASE_DEPLOYMENT_ID must be set alongside AUTOLAUNCH_BASE_DEPLOYMENT"
  end

  config :regents,
    autolaunch_base_deployment: base_deployment,
    autolaunch_base_deployment_id: base_deployment_id
end

if base_stocks_deployment != "" do
  if base_deployment == "" do
    raise "AUTOLAUNCH_BASE_STOCKS_DEPLOYMENT needs AUTOLAUNCH_BASE_DEPLOYMENT"
  end

  config :regents, :autolaunch_base_stocks_deployment, base_stocks_deployment
end

if robinhood_deployment != "" do
  config :regents, :autolaunch_robinhood_deployment, robinhood_deployment
end

# Autolaunch optional feature flags & X OAuth.
x_oauth_client_id =
  case System.get_env("X_OAUTH_CLIENT_ID") do
    value when is_binary(value) ->
      case String.trim(value) do
        "" -> nil
        trimmed -> trimmed
      end

    _missing ->
      nil
  end

config :regents, :x_oauth_client_id, x_oauth_client_id

case System.get_env("AUTOLAUNCH_LAUNCHES_OPEN") do
  nil -> :ok
  "true" -> config :regents, :prelaunch_read_only, false
  other -> raise "AUTOLAUNCH_LAUNCHES_OPEN must be true or unset, got #{inspect(other)}"
end

migrating_check? = System.get_env("REGENTS_RELEASE_COMMAND") == "migrate"

if System.get_env("AUTOLAUNCH_COVERED_CALLS") == "true" and not migrating_check? do
  path = String.trim(System.get_env("AUTOLAUNCH_BASE_COVERED_CALLS_DEPLOYMENT", ""))

  if path != "" and base_deployment != "" do
    config :regents,
      covered_calls: :on,
      autolaunch_base_covered_calls_deployment: path
  end
end

if System.get_env("AUTOLAUNCH_EXPOSURE") == "true" and not migrating_check? do
  path = String.trim(System.get_env("AUTOLAUNCH_BASE_EXPOSURE_DEPLOYMENT", ""))

  if path != "" and base_deployment != "" do
    config :regents,
      exposure: :on,
      autolaunch_base_exposure_deployment: path
  end
end

if System.get_env("AUTOLAUNCH_EARN") == "true" and not migrating_check? and base_deployment != "" do
  config :regents, earn: :on
end

for {env_name, key, required_dep} <- [
      {"AUTOLAUNCH_AGENT_BIDS", :agent_bids, base_deployment},
      {"AUTOLAUNCH_AGENT_ROBINHOOD_BIDS", :agent_robinhood_bids, robinhood_deployment},
      {"AUTOLAUNCH_AGENT_LAUNCHES", :agent_launches, base_deployment},
      {"AUTOLAUNCH_AGENT_FINISH", :agent_finish, base_deployment},
      {"AUTOLAUNCH_AGENT_STAKING", :agent_staking, base_deployment}
    ],
    System.get_env(env_name) == "true" and not migrating_check? and required_dep != "" do
  config :regents, key, :on
end

if System.get_env("AUTOLAUNCH_FINISHER_ON") == "true" and not migrating_check? do
  finisher_key = System.fetch_env!("AUTOLAUNCH_FINISHER_KEY")

  if Regents.Autolaunch.AuctionFinish.Wallet.private_key(finisher_key) == :error do
    raise "AUTOLAUNCH_FINISHER_KEY must be 0x and the 64 hex digits of a private key"
  end

  config :regents, :auction_finisher_key, finisher_key
  config :regents, Oban, queues: [autolaunch_auction_finishing: [limit: 1, paused: false]]
end

# Patchbay payments (shared RegentPayments library): facilitator defaults to CDP
# and auth is optional so a local machine boots without payment credentials.
facilitator_url =
  case System.get_env("X402_FACILITATOR_URL") do
    url when is_binary(url) and url != "" -> url
    _unset -> X402.Facilitator.Auth.CDP.facilitator_url()
  end

facilitator_auth =
  case {System.get_env("CDP_API_KEY_ID"), System.get_env("CDP_API_KEY_SECRET")} do
    {id, secret} when is_binary(id) and id != "" and is_binary(secret) and secret != "" ->
      {X402.Facilitator.Auth.CDP, api_key_id: id, api_key_secret: secret}

    _absent ->
      nil
  end

config :regent_payments, RegentPayments.Facilitator,
  url: facilitator_url,
  auth: facilitator_auth

if config_env() != :test do
  config :regent_payments, base_rpc_url: System.get_env("BASE_RPC_URL")
end

# Patchbay optional runtime configuration (OpenRouter, OpenAI, Offers, IndexNow, Moderators, Escrow).
if key = System.get_env("OPENROUTER_API_KEY") do
  config :regents, :openrouter, api_key: key
end

if key = System.get_env("OPENAI_API_KEY") do
  config :regents, :answer_watch, openai_api_key: key
end

if key = System.get_env("PATCHBAY_INDEXNOW_KEY") do
  config :regents, :indexnow_key, key
end

if shots = System.get_env("PATCHBAY_SHOTS_URL") do
  config :regents, :shots_url, shots
end

if market = System.get_env("PATCHBAY_OFFERS_MARKET") do
  config :regents, Regents.Patchbay.Offers,
    market_address: market,
    publisher_private_key: System.get_env("PATCHBAY_OFFERS_PUBLISHER_KEY")
end

if broker = System.get_env("PATCHBAY_SIWA_URL") do
  config :regents, :wallet_author, broker_url: broker
end

# The Privy accounts that run this site, comma separated (config/config.exs).
if admins = System.get_env("REGENTS_ADMINS") do
  admins = admins |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
  config :regents, :admins, admins
  config :regent_agents, admins: admins
end

migrating? = System.get_env("REGENTS_RELEASE_COMMAND") == "migrate"

# The read-only venue, the `reader` role (Regents.DatabaseConfig): the site only
# reads (`Regents.read_only?/0`), and saves no crash, as its login may not write.
read_only? = Regents.DatabaseConfig.reader?()
config :regents, :read_only, read_only?
config :error_tracker, :enabled, not read_only?

# Connected-app OAuth & hosted MCP identity tools: off by default and always off
# on the read-only venue or during migrations.
claude_connector? =
  case System.get_env("REGENTS_CLAUDE_CONNECTOR_ENABLED") do
    nil -> false
    "true" -> not migrating? and not read_only?
    _other -> raise "REGENTS_CLAUDE_CONNECTOR_ENABLED must be true or unset"
  end

hosted_signing_key = System.get_env("SIWA_HOSTED_SIGNING_KEY")

if claude_connector? and
     not (is_binary(hosted_signing_key) and
            Regex.match?(~r/\A[A-Za-z0-9_-]{32,}\z/, hosted_signing_key)) do
  raise "REGENTS_CLAUDE_CONNECTOR_ENABLED is true, so SIWA_HOSTED_SIGNING_KEY must be " <>
          "this site's hosted signing key from the sign-in service: 32 or more letters, " <>
          "digits, - or _"
end

config :regents, Regents.OAuth,
  enabled?: claude_connector?,
  issuer: site_url,
  resource: site_url && site_url <> "/mcp"

config :regent_mcp_agents, :config,
  enabled?: claude_connector?,
  hosted_signer: [
    base_url: System.get_env("SIWA_SERVER_URL"),
    key: hosted_signing_key
  ]

config :regent_agents, hosted_pairing: if(claude_connector?, do: [:claude], else: [])

database_config =
  if config_env() == :prod and migrating? do
    Regents.DatabaseConfig.release_config!()
  else
    Regents.DatabaseConfig.runtime_config!(config_env())
  end

if database_config do
  config :regents, :database_startup_enabled, true
  config :regents, Regents.Repo, database_config
end

# Each Keyfleet fleet's trait table, and card deck if it has one, ships with
# the release, named by its hash.
config :regents, Regents.Keyfleet.Traits,
  directory: Application.app_dir(:regents, "priv/keyfleet/trait_tables")

config :regents, Regents.Keyfleet.Decks,
  directory: Application.app_dir(:regents, "priv/keyfleet/decks")

# Local Stake and Redeem read the same Base endpoint as production when
# `BASE_READ_RPC_URL` names one; without it the public default in `config.exs`
# stands. Only the host is logged, because provider URLs carry the API key.
if config_env() == :dev do
  config :regents,
         :staking_snapshot_refresh_enabled,
         System.get_env("STAKING_SNAPSHOT_REFRESH_ENABLED") == "true"

  config :regents,
         :oban_cron_enabled,
         System.get_env("REGENTS_DEV_OBAN_CRON") == "true"

  config :regents,
         :autolaunch_chain_polling_enabled,
         String.trim(System.get_env("AUTOLAUNCH_BASE_DEPLOYMENT", "")) != "" or
           System.get_env("REGENTS_DEV_OBAN_CRON") == "true"

  base_read_rpc_url = String.trim(System.get_env("BASE_READ_RPC_URL", ""))

  if base_read_rpc_url != "" do
    config :regents, :base_read_rpc_url, base_read_rpc_url

    Logger.info("Development Base read endpoint host #{URI.parse(base_read_rpc_url).host}")
  end
end

if config_env() == :prod do
  # Stake and Redeem read one canonical `safe` Base block through this endpoint.
  # Development has a default in `config.exs`; production must say which
  # endpoint it trusts, so a missing value stops the boot instead of quietly
  # reading a public one.
  config :regents, :base_read_rpc_url, System.fetch_env!("BASE_READ_RPC_URL")

  config :regents, :session_options, secure: true, http_only: true

  # One JSON object a line, which Fly Sentinel reads, carrying only the visit
  # fields (RegentsWeb.VisitLog). Release commands write the same shape.
  config :logger, :default_handler,
    formatter: LoggerJSON.Formatters.Basic.new(metadata: RegentsWeb.VisitLog.fields())

  unless migrating? do
    host = String.trim(System.fetch_env!("PHX_HOST"))
    secret_key_base = System.fetch_env!("SECRET_KEY_BASE")

    if host == "" do
      raise "PHX_HOST must not be empty"
    end

    if byte_size(secret_key_base) < 64 do
      raise "SECRET_KEY_BASE must be at least 64 bytes"
    end

    config :regents, RegentsWeb.Endpoint,
      server: true,
      url: [host: host, port: 443, scheme: "https"],
      http: [
        ip: {0, 0, 0, 0, 0, 0, 0, 0},
        port: String.to_integer(System.get_env("PORT", "4000"))
      ],
      secret_key_base: secret_key_base

    # The commit the image was built from, and the Fly image this machine runs.
    config :regents, :build, %{
      commit: System.fetch_env!("SOURCE_COMMIT"),
      release: System.fetch_env!("FLY_IMAGE_REF")
    }
  end
end
