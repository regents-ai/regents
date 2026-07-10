defmodule AshPlatform.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AshPlatformWeb.Telemetry,
      {Phoenix.PubSub, name: AshPlatform.PubSub},
      # Start a worker by calling: AshPlatform.Worker.start_link(arg)
      # {AshPlatform.Worker, arg},
      # Start to serve requests, typically the last entry
      AshPlatformWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AshPlatform.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AshPlatformWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
