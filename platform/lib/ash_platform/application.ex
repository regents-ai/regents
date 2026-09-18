defmodule AshPlatform.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        AshPlatformWeb.Telemetry,
        {AshPlatform.AgentAuth.ClaimRateLimiter, []},
        {AshPlatform.OpenSea.HoldingsCache, []},
        database_child(),
        {Phoenix.PubSub, name: AshPlatform.PubSub},
        # After PubSub: a finished ENS lookup announces itself on the topic the
        # signed-in shell listens on.
        AshPlatform.Ens,
        # After PubSub: its first reading is announced to every page on the
        # topic the staking pages subscribe to.
        {AshPlatform.Staking.SnapshotCache, []},
        # Start a worker by calling: AshPlatform.Worker.start_link(arg)
        # {AshPlatform.Worker, arg},
        # Start to serve requests, typically the last entry
        AshPlatformWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AshPlatform.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp database_child do
    if Application.get_env(:ash_platform, :database_startup_enabled, false),
      do: AshPlatform.Repo
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AshPlatformWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
