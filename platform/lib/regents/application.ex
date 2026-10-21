defmodule Regents.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Every outbound TLS connection trusts castore's list, not the operating
    # system's: castore drops a compromised root as soon as Mozilla does, which a
    # Debian image can lag by weeks. Req, Finch and Mint read this list through
    # `:public_key.cacerts_get/0`, so it is loaded before anything connects.
    :ok = :public_key.cacerts_load(CAStore.file_path())
    :ok = Regents.Staking.SnapshotRefresh.attach_failure_notice()

    children =
      [
        RegentsWeb.Telemetry,
        {Regents.RateLimiter, []},
        {Regents.OpenSea.HoldingsCache, []},
        {Task.Supervisor, name: Regents.SiteTools.Reads},
        Regents.SiteTools,
        # Each paired agent's reading from the sign-in service, kept five minutes
        # and shared by the side panel and the Account page.
        Regents.Agents.ActivityReading,
        # Each agent's reading for an open side panel, unlinked from the page.
        {Task.Supervisor, name: Regents.Agents.Reads},
        database_child(),
        {Phoenix.PubSub, name: Regents.PubSub},
        # After the repository and PubSub: agent changes made on any Regent
        # site reach the Account pages showing them.
        agents_listener_child(),
        # After the repository and PubSub: a Credits balance changed on any
        # Regent site reaches the pages showing it.
        credits_listener_child(),
        staking_listener_child(),
        # After the repository: background jobs, including Credits purchase checks.
        oban_child(),
        # After PubSub: a finished ENS lookup announces itself on the topic the
        # signed-in shell listens on.
        Regents.Ens,
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

  defp agents_listener_child do
    if Application.get_env(:regents, :database_startup_enabled, false),
      do: RegentAgents.Listener
  end

  defp credits_listener_child do
    if Application.get_env(:regents, :database_startup_enabled, false),
      do: RegentCredits.Listener
  end

  defp staking_listener_child do
    if Application.get_env(:regents, :database_startup_enabled, false),
      do: Regents.Staking.SnapshotListener
  end

  # AshOban adds a queue and a sweep for every trigger in the site's domains and
  # in Regent Credits, whose purchase checks run on this site's Oban.
  defp oban_child do
    if Application.get_env(:regents, :database_startup_enabled, false) do
      {Oban,
       AshOban.config(
         Application.fetch_env!(:regents, :ash_domains) ++ [RegentCredits],
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
    do: Enum.reject(entries, &match?({_, Regents.Staking.SnapshotRefresh}, &1))

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
