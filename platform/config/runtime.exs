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

config :regent_agents, :siwa,
  url: System.get_env("SIWA_SERVER_URL"),
  audience: System.get_env("SIWA_AUDIENCE"),
  origin: site_url

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
    {String.trim(System.get_env("AUTOLAUNCH_BASE_DEPLOYMENT", "")),
     String.trim(System.get_env("AUTOLAUNCH_BASE_DEPLOYMENT_ID", "")),
     String.trim(System.get_env("AUTOLAUNCH_BASE_STOCKS_DEPLOYMENT", ""))}
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
