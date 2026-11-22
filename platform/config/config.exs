# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :regent_identity, repo: Regents.Repo, ash_domains: [RegentIdentity]

config :regent_payments,
  repo: Regents.Repo,
  site: "patchbay",
  ash_domains: [RegentPayments],
  offers: [
    Regents.Patchbay.Payments.AgentTip,
    Regents.Patchbay.Payments.SpecialPost
  ],
  payment_chain: %{name: "Base", rpc_url: "https://mainnet.base.org"},
  wallet_proof: [name: "Regents", version: "1", endpoint: RegentsWeb.Endpoint]

# Agents pair with a person's account through the agent pairing every Regent site
# shares (RegentAgents). `allowed` is what an agent may do here in each status,
# as GET /api/agents/v1/whoami tells it and priv/public/agents.md and the tools
# in priv/tool_manifest.json list it: true to the routes and policies, so change
# them together. `person` names the person, by their profile code, when the
# sign-in service asks before giving an agent a hello card; the service's
# `origin` is in config/runtime.exs.
config :regent_agents,
  repo: Regents.Repo,
  pubsub: Regents.PubSub,
  notifications: Regents.Notifications,
  account: {Regents.Account.AgentAccount, :account},
  person: {Regents.Account.AgentAccount, :person},
  allowed: %{
    "not_paired" => [
      "Read this site's public pages and docs, also with the regents_about, regents_products, regents_product, regents_research_list, regents_research_paper, regents_articles_list, regents_article, regents_literature and regents_public_profile tools.",
      "Check your status here at any time, also with the regents_agent_whoami tool.",
      "Pair with the code your person makes with Pair New Agent on their Agents page."
    ],
    "person_not_here" => [
      "Read this site's public pages and docs, also with the regents_about, regents_products, regents_product, regents_research_list, regents_research_paper, regents_articles_list, regents_article, regents_literature and regents_public_profile tools.",
      "Check your status here at any time, also with the regents_agent_whoami tool.",
      "Reading for your person answers person_not_here until your person signs in on this site."
    ],
    "paired" => [
      "Read this site's public pages and docs, also with the regents_about, regents_products, regents_product, regents_research_list, regents_research_paper, regents_articles_list, regents_article, regents_literature and regents_public_profile tools.",
      "Check your status here at any time, also with the regents_agent_whoami tool, and check in for your person.",
      "Read your person's account, verified name claims and staking position, also with the regents_account, regents_claims and regents_stake_position tools.",
      "Read your person's Points, also with the account_points tool.",
      "You can never use your person's wallet, change their account or pair other agents."
    ]
  },
  ash_domains: [RegentAgents]

# The Privy accounts that run this site: they publish articles, read the saved
# errors at /admin/errors and the messages at /admin/messages, and may remove an
# agent's picture at /admin/pictures (`Regents.admin?/1`, `RegentAgents.Checks.Admin`).
# Set at runtime (config/runtime.exs).
config :regents, :admins, []

# Regent Points: one private Points ledger per account, shared by every Regent
# site. Regents owns the `regent_points` schema's migrations and is the one site
# that tallies the NFT bonus at the end of each 30-day period. Earning is off here;
# config/prod.exs sets the start time and the approved rules for the live site.
config :regent_points,
  repo: Regents.Repo,
  pubsub: Regents.PubSub,
  accounts: Regents.Account.Points.Accounts,
  chain_client: Regents.Account.Points.ChainClient,
  ash_domains: [RegentPoints],
  program_id: "regents-points-v1",
  starts_at: nil,
  approved_rules: [],
  adapters: %{
    "account.activated" => Regents.Account.Points.AccountActivated,
    "agent.activated" => Regents.Account.Points.PairedAgent,
    "social.farcaster" => Regents.Account.Points.LinkedSocial,
    "social.github" => Regents.Account.Points.LinkedSocial,
    "social.x" => Regents.Account.Points.LinkedSocial
  }

# Ash 3.33 requires an explicit string length unit. Codepoints match how
# PostgreSQL counts `length()`, so `max_length` bounds stored size; graphemes
# (`:mixed`) do not, because one grapheme can carry unbounded combining marks
# (CVE-2026-82752).
config :ash, default_string_length_count: :codepoints

# `search_terms(term, :all | :any)`: how every Patchbay search reads the words typed.
config :ash, custom_expressions: [Regents.Patchbay.Forum.SearchTerms]

config :mime, :types, %{"application/yaml" => ["yaml"]}

config :regents,
  local_showcase: false,
  ash_domains: [
    Regents.Account.Names,
    Regents.Account.Accounts,
    Regents.Account.Agents,
    Regents.Account.Formation,
    Regents.OpenSea,
    Regents.Redeem,
    Regents.Stake,
    Regents.PaperProDaily,
    Regents.Account.Points,
    Regents.Blog,
    Regents.Messages,
    Regents.Updates,
    Regents.Techtree.ModelClimb,
    Regents.Techtree.Catalog,
    Regents.Techtree.Network,
    Regents.Techtree.WalletBench,
    Regents.Techtree.Projects,
    Regents.Techtree.Enquiries,
    Regents.Techtree.Watchdog,
    Regents.Patchbay.Forum,
    Regents.Patchbay.Members,
    Regents.Patchbay.Assist,
    Regents.Patchbay.AnswerWatch,
    Regents.Patchbay.Messages,
    Regents.Patchbay.Offers,
    Regents.Patchbay.WalletBench,
    Regents.Autolaunch,
    Regents.Autolaunch.CoveredCalls,
    Regents.Autolaunch.Exposure,
    Regents.Autolaunch.Earn,
    # Keyfleet's, which Regents.Keyfleet.domains/0 names.
    Regents.Keyfleet.Fleets,
    Regents.Keyfleet.Rooms,
    Regents.Keyfleet.Polls,
    Regents.Keyfleet.Seasons,
    Regents.Keyfleet.Dms,
    Regents.Keyfleet.Agents,
    Regents.Keyfleet.Keys,
    Regents.Keyfleet.Chain,
    Regents.Keyfleet.Proposals,
    Regents.Keyfleet.Treasury,
    Regents.Keyfleet.Graph,
    Regents.Keyfleet.WalletSteps,
    Regents.Keyfleet.Early,
    Regents.Keyfleet.Notebooks,
    Regents.Keyfleet.Code,
    Regents.Keyfleet.Projects,
    Regents.Keyfleet.Usage,
    Regents.Keyfleet.Atlas,
    RegentsWeb.Keyfleet.AgentTools
  ],
  generators: [timestamp_type: :utc_datetime]

config :regents,
  fleet_feed_wait_ms: 2_000,
  agent_waits_per_address: 4,
  agent_waits_total: 600,
  base_read_rpc_url: "https://base-rpc.publicnode.com",
  robinhood_read_rpc_url: "https://rpc.mainnet.chain.robinhood.com",
  earn_products: [
    %{
      id: "aave-usdc",
      chain_id: 8453,
      protocol: "Aave",
      market: "Aave V3 on Base",
      asset: "USDC",
      decimals: 6,
      pool: "0xa238dd80c259a72e81d7e4664a9801593f98d1c5",
      asset_address: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"
    }
  ],
  earn_terms_kept_ms: 10_000,
  stock_list_kept_ms: 60_000,
  convert_read_timeout: 30_000,
  share_video_saved_bytes: 5_000_000_000,
  autolaunch_share_video_renderer: RegentsWeb.Autolaunch.ShareVideo.Render

config :regents, Regents.Autolaunch.ChainRefresh,
  readers: [
    Regents.Autolaunch.ChainHead,
    Regents.Autolaunch.AuctionMarket,
    Regents.Autolaunch.Robinhood.Discovery,
    Regents.Autolaunch.AuctionActivity,
    Regents.Autolaunch.TokenTrades,
    Regents.Autolaunch.LaunchDiscovery.Discover,
    Regents.Autolaunch.RegentFacts,
    Regents.Autolaunch.CoveredCalls.Book
  ]

config :regents, ecto_repos: [Regents.Repo]

# The read-only venue turns this on at boot (config/runtime.exs, `Regents.read_only?/0`).
config :regents, :read_only, false

# The commit and Fly image a deployed machine runs; production sets both at boot.
config :regents, :build, %{commit: nil, release: nil}

# The home colour every page carries as `data-home`: "ink", "tangerine" or "blue".
config :regents, :home_colour, "blue"

# Background jobs live in the site's own schema, beside its tables. Queues hear
# about new jobs through Erlang process groups, across the site's machines.
# AshOban adds each trigger's sweep to `cron`. `points` checks and awards Points;
# `points_chain` reads NFT holdings for the period-end bonus, tallied daily only on
# this site.
config :regents, Oban,
  repo: Regents.Repo,
  prefix: "regents_app",
  notifier: Oban.Notifiers.PG,
  queues: [
    default: 1,
    points: 5,
    points_chain: 2,
    stake_reads: 1,
    techtree_watchdog: 2,
    keyfleet_default: 5,
    keyfleet_notebook_hubs: 1,
    keyfleet_notebook_backups: 1,
    keyfleet_code_store: 2,
    keyfleet_avatars: 2,
    keyfleet_key_art: 1,
    keyfleet_chain: 10,
    keyfleet_seasons: 1,
    autolaunch_default: 1,
    autolaunch_chain: 4,
    autolaunch_launch_listing: 1,
    autolaunch_outside_calls: 3,
    autolaunch_stock_volume: 1,
    autolaunch_stock_admissions: 1,
    autolaunch_share_videos: 1,
    autolaunch_auction_finishing: [limit: 1, paused: true],
    patchbay_assist: 4,
    patchbay_fees: 1,
    patchbay_jev: 2,
    patchbay_webhooks: 10,
    patchbay_lapsed_subscriptions: 1,
    patchbay_site_checks: 2,
    patchbay_site_pictures: 1,
    patchbay_post_checks: 1,
    patchbay_notifications: 5,
    patchbay_answer_watch: 2,
    patchbay_outside_calls: 2,
    patchbay_escrow_reads: 2,
    patchbay_offer_reads: 1,
    patchbay_escrow_records: 1,
    patchbay_connected_apps: [limit: 1, paused: true],
    patchbay_default: 1
  ],
  cron: [
    crontab: [
      {"15 0 * * *", RegentPoints.TallyPeriods},
      {"@reboot", Regents.Stake.SnapshotRefresh},
      # Every five minutes, and early after a confirmed on-chain press or a press
      # of the read-again icon (Regents.Chain.Refresh).
      {"*/5 * * * *", Regents.Stake.SnapshotRefresh},
      {"17 4 * * *", Regents.ErrorPruner},
      # From the Points start, the one-time points for what accounts already had.
      {"@hourly", RegentPoints.StartAwards},
      # Autolaunch chain watch.
      {"* * * * *", Regents.Autolaunch.ChainWatch},
      # Patchbay maintenance, sweeps, CVE watch and AnswerWatch.
      {"47 4 * * *", Regents.Patchbay.Forum.PostCheckPruner},
      {"*/5 * * * *", Regents.Patchbay.Forum.SiteCheckSweep},
      {"*/5 * * * *", Regents.Patchbay.Forum.ListedSitePictureSweep},
      {"0 6 * * 1", Regents.Patchbay.AnswerWatch.Ask},
      {"@hourly", Regents.Patchbay.IndexNow},
      {"0 * * * *", Regents.Patchbay.Incidents.CveNow},
      # Keyfleet's scheduled maintenance, chain watchers, notebooks, seasons and Atlas.
      {"*/10 * * * *", Regents.Keyfleet.Notebooks.Reconcile},
      {"31 3 * * *", Regents.Keyfleet.Notebooks.DailyBackup},
      {"*/5 * * * *", Regents.Keyfleet.Chain.Watch},
      {"47 4 * * *", Regents.Keyfleet.Notebooks.RunPagePruner},
      {"41 * * * *", Regents.Keyfleet.Keys.DeckEndCheck},
      {"13 * * * *", Regents.Keyfleet.Usage.Count},
      {"* * * * *", Regents.Keyfleet.Atlas.Fill},
      {"29 * * * *", Regents.Keyfleet.Atlas.ReadHubs},
      {"7 * * * *", Regents.Keyfleet.Keys.PresenceTimer},
      {"1-59/10 * * * *", Regents.Keyfleet.Seasons.Turns},
      # One line for each kind of shared reading a producer rereads on notice.
      {"* * * * *", Regents.SharedReading.Heal, args: %{kind: "points_board"}},
      {"* * * * *", Regents.SharedReading.Heal, args: %{kind: "keyfleet_fleet_agents"}},
      {"* * * * *", Regents.SharedReading.Heal, args: %{kind: "keyfleet_key_agents"}},
      {"* * * * *", Regents.SharedReading.Heal, args: %{kind: "keyfleet_fleet_now"}},
      {"* * * * *", Regents.SharedReading.Heal, args: %{kind: "keyfleet_fleet_proposals"}},
      {"* * * * *", Regents.SharedReading.Heal, args: %{kind: "keyfleet_fleet_treasury"}},
      {"* * * * *", Regents.SharedReading.Heal, args: %{kind: "keyfleet_share_card"}},
      {"* * * * *", Regents.SharedReading.Heal, args: %{kind: "keyfleet_project_cards"}},
      {"* * * * *", Regents.SharedReading.Heal, args: %{kind: "keyfleet_proposal"}},
      {"* * * * *", Regents.SharedReading.Heal, args: %{kind: "wallet_bench"}},
      {"* * * * *", Regents.SharedReading.Heal, args: %{kind: "hidden_sites"}}
    ]
  ],
  pruner: [max_age: {7, :days}],
  lifeline: [rescue_after: {10, :minutes}]

config :regents, :metrics_listener, ip: {127, 0, 0, 1}, port: 9091

config :regents, Regents.Repo,
  database: "regents_disabled",
  hostname: "127.0.0.1",
  port: 1,
  pool_size: 1

# Each paired agent's reading from the sign-in service, kept five minutes. Older
# readings leave with the generation the collector drops every ten minutes.
config :regents, Regents.Account.Agents.ActivityReading,
  gc_interval: :timer.minutes(10),
  max_size: 10_000

# What the papers page shows, kept one minute.
config :regents, RegentsWeb.PaperProDaily.Feed,
  gc_interval: :timer.minutes(10),
  max_size: 1_000

# Patchbay's home page board figures: one reading, kept a minute.
config :regents, Regents.Patchbay.Forum.BoardActivity, gc_interval: :timer.minutes(10)
config :regents, Regents.Techtree.WalletBench.Reading, gc_interval: :timer.minutes(10)

# Each Patchbay question list's thread count, kept a minute. Older counts leave
# with the generation the collector drops every ten minutes.
config :regents, Regents.Patchbay.Forum.FeedCount,
  gc_interval: :timer.minutes(10),
  max_size: 10_000

# Keyfleet's share pictures drawn for link previews
# (`RegentsWeb.Keyfleet.SharePictures`), swept every ten minutes, so one no
# one reads leaves within twenty. There is one for each of the two fleets with
# a picture and one for each of their projects (a Key holds at most six), and
# a new version of one each time what it shows changes and it is asked for;
# each is a PNG of 50 to 70 kilobytes. 256 holds both fleets' and up to 120
# projects' pictures with a version moving on for each, under 20 megabytes;
# past it the ones not read since the last sweep go first, and are drawn again
# when next asked for.
config :regents, RegentsWeb.Keyfleet.SharePictures,
  gc_interval: :timer.minutes(10),
  max_size: 256

config :regents, :session_bootstrap_rate_limit, limit: 30, window_seconds: 300
config :regents, :chain_read_rate_limit, limit: 30, window_seconds: 60
# Messages left for the team (`Regents.Messages`): each person, with their paired
# agents, and each network leaves a few an hour.
config :regents, :message_rate_limit, limit: 10, window_seconds: 3600
config :regents, :message_address_rate_limit, limit: 30, window_seconds: 3600
# Email addresses left for updates (`Regents.Updates`): each network leaves a few a minute.
config :regents, :updates_rate_limit, limit: 5, window_seconds: 60
# The site's named allowances (`Regents.Limits`), `<product>_<name>: [limit:,
# window_seconds:]`.
config :regents, :limits,
  # Autolaunch wallet & page read budgets.
  wallet_read: [limit: 30, window_seconds: 60],
  page_read: [limit: 30, window_seconds: 60],
  # Listings one address's open Autolaunch pages read (a changed option, a
  # search, Load more): as many a minute as the address has reads of the site.
  autolaunch_list_reads: [limit: 120, window_seconds: 60],
  # Posts one agent wallet writes as one Keyfleet Key, in rooms and on its thread:
  # as many as people get.
  keyfleet_agent_posts: [limit: 300, window_seconds: 3600],
  # Keyfleet workspace writes per wallet in each fleet: two a second, more than
  # real agent work needs.
  keyfleet_graph_writes: [limit: 120, window_seconds: 60],
  # A person's presses of Keyfleet's Treasury refresh: one every 30 seconds
  # (Sean, 20 October 2026).
  keyfleet_treasury_refresh: [limit: 1, window_seconds: 30],
  # Chain figures one address's open Keyfleet pages read: a wallet panel's
  # first read, one a changed form or the open wallet starts, and the panel's
  # own rereads on its timer; the Key window's rewards, when not read in the
  # last 30 seconds, and its slice. As many a minute as Autolaunch's lists. No
  # press is counted.
  keyfleet_wallet_reads: [limit: 120, window_seconds: 60],
  # Moves of the sea behind one address's open Keyfleet pages to another fleet,
  # or to every fleet: twice what a quick visit spends (22 a minute, reading
  # each page for 2 seconds), so two people behind one address are not held.
  # Past them the sea stays as it is drawn.
  keyfleet_sea_moves: [limit: 45, window_seconds: 60],
  # Reads of a member's own ships by the sea behind one address's open
  # Keyfleet pages, one on coming to a fleet they are a member of and one a
  # burst of that fleet's news: twice what three open pages read in a busy
  # fleet's minute (81, news every half second), so two members behind one
  # address are not held. Past them the sea keeps the ships it has until the
  # next news.
  keyfleet_sea_crew_reads: [limit: 180, window_seconds: 60],
  # Searches one address's open Keyfleet pages run, Show more included: one a
  # second.
  keyfleet_searches: [limit: 60, window_seconds: 60],
  # Further pages one address's open Patchbay site directories load (Load more,
  # or scrolling to the end): the whole directory, 88 more pages of 30 on
  # patchbay.help, within a minute, and as many as the address has reads of
  # the site, so a page costs what its plain Next link does.
  patchbay_directory_reads: [limit: 120, window_seconds: 60],
  # Thread views one address records on Patchbay: a reader opens a new thread
  # every three seconds at most. Past them the page is served and only its
  # count misses the view.
  patchbay_thread_views: [limit: 20, window_seconds: 60],
  patchbay_message: [limit: 10, window_seconds: 3600],
  patchbay_message_address: [limit: 30, window_seconds: 3600],
  patchbay_search_address: [limit: 300, window_seconds: 60],
  patchbay_wallet_read: [limit: 30, window_seconds: 60],
  # Reads one address's open Techtree Projects pages make as they connect and
  # move between the list and a project: as many a minute as the address has
  # reads of the site.
  techtree_project_reads: [limit: 120, window_seconds: 60],
  # Contact form enquiries on Techtree's home and service pages: five an hour
  # per client address.
  techtree_enquiries: [limit: 5, window_seconds: 3600]

# Patchbay domain configuration (OpenRouter, AnswerWatch, Offers, Incidents, WalletBench, Assist).
config :regents, :openrouter,
  jev_url: "https://openrouter.ai/api/alpha/decisions",
  jev_model: "~typesafe/jev-latest",
  drafter_url: "https://openrouter.ai/api/v1/chat/completions",
  drafter_model: "openai/gpt-5.6-terra"

config :regents, :answer_watch,
  chatgpt_url: "https://api.openai.com/v1/responses",
  chatgpt_model: "gpt-5.6-terra",
  perplexity_url: "https://openrouter.ai/api/v1/chat/completions",
  perplexity_model: "perplexity/sonar"

config :regents, Regents.Patchbay.Agents.HostedAddress,
  gc_interval: :timer.hours(12),
  max_size: 100_000

config :regents, Regents.Patchbay.WalletBench.RunRecords,
  gc_interval: :timer.minutes(10),
  max_size: 1_000,
  allocated_memory: 100_000_000,
  gc_memory_check_interval: :timer.seconds(10)

config :regents, Regents.Patchbay.WalletBench.Board, statement_timeout: 5_000

config :regents, Regents.Patchbay.Incidents.CveNow,
  enabled?: true,
  url: "https://cve.now/api/v1",
  page_size: 50,
  reads_per_run: 20

config :regents, Regents.Patchbay.Forum.SiteCheckSweep, enabled?: true
config :regents, Regents.Patchbay.Forum.ListedSitePictureSweep, enabled?: true, per_run: 1
config :regents, Regents.Patchbay.Forum.EventSubscription, webhooks: Regent.MCPEvents

config :regents, Regents.Patchbay.Offers,
  market_address: nil,
  chain_id: 8453,
  chain_name: "Base",
  wallet_rpc_url: "https://mainnet.base.org",
  from_block: 0,
  policy: "patchbay-policy-v1",
  publisher_private_key: nil,
  client: Regents.Patchbay.Offers.Node

config :regents, :assist_read_only_tools, %{
  "patchbay.help" =>
    ~w(get_patchbay_help get_webmcp_guide read_site_directory search_threads get_thread get_tool_history get_agent_profile)
}

config :regents, :shots_url, "http://patchbay-shots.flycast"
config :regents, :x402_test_pay_to, "0x786C67651BcB148f5A383A150E78bD4Ed9f64f7b"
config :regents, :incident_files, ["priv/patchbay/incidents/*.md"]

config :regents, :error_links, %{
  "not_signed_in" => "bc85f337-9965-4a8c-9a4e-ea875b3a55ce",
  "agent_not_paired" => "54444861-6b25-4918-abb9-dd6f98b76380",
  "person_not_here" => "d6a3cc57-124c-41ff-a8fb-bc7d2b1095cc",
  "no_touch_id" => "f308a148-c8af-47ea-845d-7c402c07c76d",
  "key_helper_not_answering" => "f308a148-c8af-47ea-845d-7c402c07c76d",
  "locked_key_needs_mac" => "f308a148-c8af-47ea-845d-7c402c07c76d",
  "code_sign_in" => "4a53f1bb-e031-4142-b268-cfe32a1619f0"
}

config :regents, :name_first, :ens
config :regents, :build, %{commit: "local", release: nil}

# Rate limits key on the direct peer. Production turns on Fly's client header.
config :regents, :behind_fly_proxy, false

config :regents, :base_read_rpc_url, "https://base-rpc.publicnode.com"
# ENS lives on Ethereum mainnet, which has no public endpoint this product is
# willing to trust: without one named at boot, no name or picture is looked up.
config :regents, :ethereum_read_rpc_url, nil
config :regents, :ens_lookup_deadline_ms, 4_000
config :regents, :ens_avatar_deadline_ms, 10_000
config :regents, :app_surfaces, true
config :regents, :opensea_api_key, nil
config :regents, :opensea_live_lookups_per_minute, 60
config :regents, :opensea_lookups_per_minute, 6
# Also bounds how often one address may be reset: once per window.
config :regents, :opensea_holdings_cache_ttl_ms, 15_000

# One shared Oban job warms and refreshes the durable staking projection every
# five minutes. Development disables this automatic work unless explicitly enabled.
config :regents, :staking_snapshot_refresh_enabled, true

# Who reads a chain again when a person's action may have changed it
# (`Regents.Chain.Refresh`).
config :regents, Regents.Chain.Refresh, readers: [Regents.Stake.SnapshotCache]

# Techtree's catalog bundle this build serves, and the release channel it
# belongs to. `catalog_root` holds the generated `techtree-python` export; it is
# populated by `scripts/sync_catalog.exs` at release time and read only by the
# importer and the exact-byte read path. Both are overridable at runtime.
config :regents, Regents.Techtree.Catalog,
  catalog_root: {:priv, "techtree/catalog"},
  channel: "development"

# Techtree's public run log: the largest submission it reads, and how often one
# address, or one paired agent across every address it sends from, may publish.
# A proof bundle carries digests and scores and no transcripts, so two mebibytes
# is generous by a factor of six and still small enough that an oversized body is
# refused before it is read.
config :regents, Regents.Techtree.Network,
  maximum_body_bytes: 2_097_152,
  rate_limit: [limit: 10, window_seconds: 60],
  agent_rate_limit: [limit: 10, window_seconds: 60]

config :regents, Regents.Techtree.Watchdog,
  max_hosts_per_account: 20,
  max_routes_per_account: 100

# The example comparison at /techtree/examples/tdd: the files one local `techtree
# forge` comparison wrote, committed as they are (RegentsWeb.Techtree.TddShowcase).
# The export link names the techtree repository at the commit that added them.
config :regents, RegentsWeb.Techtree.TddShowcase,
  folder: {:priv, "techtree/examples/tdd-showcase"},
  repository_url: "https://github.com/regents-ai/techtree",
  export_revision: "808c280608a0599bbd5825e61534de8570992715"

# The public addresses Keyfleet's agent guides give an agent: the sign-in
# server, a fleet's code, and a fleet's notebooks at https://<fleet>.<suffix>
# (RegentsWeb.Keyfleet.AgentFilesController).
config :regents,
  keyfleet_siwa_origin: "https://siwa.regents.sh",
  keyfleet_code_origin: "https://code.keyfleet.ai",
  keyfleet_notebooks_host_suffix: "notebooks.keyfleet.ai"

# Keyfleet's core (Regents.Keyfleet), with keyfleet.ai's own figures. No address of
# another service, key or secret is set here: each is set by the slice that puts
# its reader to use (lib/regents/keyfleet/SOURCE.json, "settings_unset").
#
# How long an agent's waiting request is held open with nothing new, before it
# answers and the agent asks again: well inside the 60 seconds the proxy keeps an
# idle request open.
config :regents, :keyfleet_agent_wait_ms, 20_000

# How long a member's open fleet page waits after a notice that something
# happened in the fleet before it reads the hall's feed again, so a burst of
# changes is read once.
config :regents, :keyfleet_fleet_feed_wait_ms, 2_000

# The longest the first read of every fleet's shared reading of what it is doing
# now and of its proposals may take as the site starts; a fleet not read by then
# shows as not read until its next notice or the minute's heal.
config :regents, :keyfleet_first_read_ms, 5_000

# The public address agents' pictures are read from: keyfleet.ai's picture
# bucket (Regents.Keyfleet.Agents.AvatarBucket). Nothing here writes to it.
config :regents, :keyfleet_avatar_bucket,
  public_url: "https://keyfleet-pictures.fly.storage.tigris.dev"

# The chain a fleet's wallet buttons send on, by the chain id its deployment
# records, with its name in the page's words (Regents.Keyfleet.WalletSteps). Its
# public rpc_url goes to the wallet; the server reads Base only through
# :base_read_rpc_url.
config :regents, :keyfleet_wallet_chains, %{
  8453 => %{name: "Base", rpc_url: "https://mainnet.base.org"}
}

# Saves of proposal words per signed-in person: twenty an hour. Each press of
# Propose saves once, so this leaves room to redo a proposal many times while
# keeping one account to about 80 KB of words an hour.
config :regents, :keyfleet_proposal_words_rate_limit, limit: 20, window_seconds: 3600

# Each deployed fleet's history is read every five minutes
# (Regents.Keyfleet.Chain.ReadFleet).
config :regents, :keyfleet_chain, pass_interval_seconds: 300

# Each fleet's work graph lives in a host of its own; a new host replays its
# fleet's whole log before it answers, so it gets far longer than a command does.
# Each fleet's read tables are copied from its log after every write, and every
# `catch_up_interval` anyway; a write waits up to `projection_wait` for its change
# to be readable. The site asks the graph machine under a pass lasting
# `pass_ttl_seconds` (Regents.Keyfleet.Graph.Client). `enabled: false`: no writer
# runs beside the site.
config :regents, :keyfleet_graph,
  enabled: false,
  hello_timeout: 60_000,
  reply_timeout: 5_000,
  check_timeout: 1_000,
  restart_min: 1_000,
  restart_max: 30_000,
  catch_up_interval: 5_000,
  projection_wait: 2_000,
  pass_ttl_seconds: 30

# Each fleet's private notebook hub (Regents.Keyfleet.Notebooks). `fleets` maps a
# fleet id to its hub's private address: none here, so no fleet has a hub. A person is
# checked again at most every `access_ttl_ms`; a Key changing hands ends their
# access at once. Someone made an editor of the fleet's hub projects is not asked
# of the hub again for `editor_ttl_ms`. An "Open notebooks" link works once, for
# `handoff_ttl_seconds`, and the notebook sign-in it sets lasts `session_max_age`
# seconds. A kept page is copied up to `saved_page_max_bytes`; an agent reads one
# in an answer of at most `page_answer_max_bytes`, each text in it cut at
# `page_value_max_bytes`. A workspace page waits `page_timeout_ms` for the hub, a
# fleet's search `search_timeout_ms`, and a new session `session_start_timeout_ms`
# (the runner allows 120 seconds to boot, plus creation and notebook setup). A
# fleet may have `max_sessions` notebook sessions open at once.
config :regents, :keyfleet_notebooks,
  fleets: %{},
  pass_ttl_seconds: 120,
  access_ttl_ms: 30_000,
  editor_ttl_ms: 10 * 60 * 1000,
  handoff_ttl_seconds: 60,
  session_max_age: 12 * 60 * 60,
  max_request_bytes: 32 * 1024 * 1024,
  saved_page_max_bytes: 16 * 1024 * 1024,
  page_answer_max_bytes: 256 * 1024,
  page_value_max_bytes: 16 * 1024,
  hub_timeout_ms: 30_000,
  page_timeout_ms: 5_000,
  search_timeout_ms: 3_000,
  session_start_timeout_ms: 180_000,
  max_sessions: 10

# Each fleet's code, in Keyfleet's own code store (Regents.Keyfleet.Code). Requests
# to the store carry a pass lasting `pass_ttl_seconds`. A person holding a Key is
# checked again at most every `access_ttl_ms` (an agent on every request), a
# person's git password lasts `password_ttl_seconds`, and one request carries at
# most `max_pack_bytes`, each read waiting at most `body_idle_ms` and the whole
# body at most `body_timeout_ms`. A workspace page waits `page_timeout_ms` for the
# store, and shows files up to `file_max_bytes`.
config :regents, :keyfleet_code,
  pass_ttl_seconds: 120,
  access_ttl_ms: 30_000,
  password_ttl_seconds: 12 * 60 * 60,
  max_pack_bytes: 100 * 1024 * 1024,
  body_idle_ms: 15_000,
  body_timeout_ms: 600_000,
  node_timeout_ms: 120_000,
  page_timeout_ms: 5_000,
  file_max_bytes: 512 * 1024

config :regents, :session_options,
  store: :cookie,
  key: "_regents_key",
  signing_salt: "OLoeAaio",
  same_site: "Lax",
  secure: false,
  http_only: true,
  # A sign-in lasts 30 days; Regents.Account.Accounts.SessionAuthority refuses it after that too.
  max_age: 30 * 24 * 60 * 60

# Configure the endpoint
config :regents, RegentsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [
      html: RegentsWeb.ErrorHTML,
      json: RegentsWeb.ErrorJSON,
      md: RegentsWeb.ErrorMD
    ],
    layout: false
  ],
  pubsub_server: Regents.PubSub,
  live_view: [signing_salt: "RH19ZPg2"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.28.2",
  regents: [
    args:
      ~w(js/app.ts js/privy_bridge.tsx --bundle --splitting --format=esm --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=. --loader:.woff2=file --loader:.woff=file --loader:.ttf=file),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Mix.Project.deps_path(), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :visit, :actor, :surface, :product, :event, :error_type]

# Failed requests, pages and jobs are saved in the site's own schema and shown
# to the site's admins at /admin/errors. Only server faults, and only a job's last
# attempt, are saved (Regents.ErrorIgnorer), only where each one happened is kept
# (Regents.ErrorFilter), and Regents.ErrorPruner clears each one a week after it
# was last seen.
config :error_tracker,
  repo: Regents.Repo,
  otp_app: :regents,
  prefix: "regents_app",
  ignorer: Regents.ErrorIgnorer,
  filter: Regents.ErrorFilter

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Domainatrex reads the list of public suffixes shipped inside the package; builds
# never fetch it.
config :domainatrex, fetch_latest: false

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
