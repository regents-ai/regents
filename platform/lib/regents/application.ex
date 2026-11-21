defmodule Regents.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  use Boundary,
    top_level?: true,
    deps: [Regents, RegentsWeb, Regents.Stake]

  use Application

  @impl true
  def start(_type, _args) do
    # Every outbound TLS connection trusts castore's list, not the operating
    # system's: castore drops a compromised root as soon as Mozilla does, which a
    # Debian image can lag by weeks. Req, Finch and Mint read this list through
    # `:public_key.cacerts_get/0`, so it is loaded before anything connects.
    :ok = :public_key.cacerts_load(CAStore.file_path())
    :ok = Regents.Stake.SnapshotRefresh.attach_failure_notice()
    :ok = RegentHttp.ErrorSaving.attach()
    :ok = RegentsWeb.VisitLog.Events.attach()

    children =
      [
        RegentsWeb.Telemetry,
        {Regents.RateLimiter, []},
        {Regents.OpenSea.HoldingsCache, []},
        {Task.Supervisor, name: Regents.SiteTools.Reads},
        Regents.SiteTools,
        # Each paired agent's reading from the sign-in service, kept five minutes
        # and shared by the account menu and the Agents page.
        Regents.Account.Agents.ActivityReading,
        # What the papers page shows, kept a minute and shared by every open of it.
        RegentsWeb.PaperProDaily.Feed,
        # Patchbay's home page board figures, kept a minute.
        Regents.Patchbay.Forum.BoardActivity,
        # Each Patchbay question list's thread count, kept a minute.
        Regents.Patchbay.Forum.FeedCount,
        # Room for two Patchbay word searches at once.
        Regents.Patchbay.Forum.SearchSlots,
        # Each agent's reading for an open account menu, unlinked from the page.
        {Task.Supervisor, name: Regents.Account.Agents.Reads},
        # Each product's health read for /api/v1/health, unlinked from the request.
        {Task.Supervisor, name: Regents.Products.Health},
        database_child(),
        {Phoenix.PubSub, name: Regents.PubSub},
        # After the repository and PubSub: a pairing or the staking figures
        # changed on any Regent site reach the pages showing them.
        shared_changes_child(),
        # After the repository: background jobs.
        oban_child(),
        # After PubSub: a finished ENS lookup announces itself on the topic the
        # signed-in shell listens on.
        Regents.Account.Ens,
        # After PubSub: the figures every reader they admit sees alike, and the
        # Points board read once for all of them.
        Regents.SharedReading,
        points_board_child(),
        # Start a worker by calling: Regents.Worker.start_link(arg)
        # {Regents.Worker, arg},
        # Start to serve requests, typically the last entry
        RegentsWeb.Endpoint,
        metrics_child()
      ]
      |> Enum.reject(&is_nil/1)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Regents.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp database_child do
    if Application.get_env(:regents, :database_startup_enabled, false),
      do: Regents.Repo
  end

  defp shared_changes_child do
    if Application.get_env(:regents, :database_startup_enabled, false),
      do: Regents.SharedChanges
  end

  # AshOban adds a queue and a sweep for every trigger in the site's domains. Every
  # job writes, so the read-only venue (`Regents.read_only?/0`) runs none.
  defp oban_child do
    if Application.get_env(:regents, :database_startup_enabled, false) and
         not Regents.read_only?() do
      {Oban,
       AshOban.config(
         Application.fetch_env!(:regents, :ash_domains),
         staking_jobs(Application.fetch_env!(:regents, Oban))
       )}
    end
  end

  defp staking_jobs(config) do
    if Application.get_env(:regents, :staking_snapshot_refresh_enabled, false),
      do: config,
      else: update_in(config, [:cron, :crontab], &without_snapshot_refresh/1)
  end

  defp without_snapshot_refresh(entries),
    do: Enum.reject(entries, &match?({_, Regents.Stake.SnapshotRefresh}, &1))

  # The Points board is read only where pages are served, so a task never reads
  # the database before it asks to. The read-only venue has no one signed in to
  # show it to, and no grant on the Points tables.
  defp points_board_child do
    if Phoenix.Endpoint.server?(:regents, RegentsWeb.Endpoint) and not Regents.read_only?(),
      do: Regents.Account.Points.Board
  end

  # Metrics are served beside the site, never by a process that only runs a task.
  defp metrics_child do
    if Phoenix.Endpoint.server?(:regents, RegentsWeb.Endpoint),
      do: RegentsWeb.Metrics
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RegentsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
