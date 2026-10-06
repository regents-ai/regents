defmodule Regents.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        RegentsWeb.Telemetry,
        {Regents.RateLimiter, []},
        {Regents.OpenSea.HoldingsCache, []},
        database_child(),
        {Phoenix.PubSub, name: Regents.PubSub},
        # After the repository and PubSub: agent changes made on any Regent
        # site reach the Account pages showing them.
        agents_listener_child(),
        # After the repository: background jobs, including Credits purchase checks.
        oban_child(),
        # After PubSub: a finished ENS lookup announces itself on the topic the
        # signed-in shell listens on.
        Regents.Ens,
        # After PubSub: its first reading is announced to every page on the
        # topic the staking pages subscribe to.
        {Regents.Staking.SnapshotCache, []},
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

  # AshOban adds a queue and a sweep for every trigger in the site's domains and
  # in Regent Credits, whose purchase checks run on this site's Oban.
  defp oban_child do
    if Application.get_env(:regents, :database_startup_enabled, false) do
      {Oban,
       AshOban.config(
         Application.fetch_env!(:regents, :ash_domains) ++ [RegentCredits],
         Application.fetch_env!(:regents, Oban)
       )}
    end
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
