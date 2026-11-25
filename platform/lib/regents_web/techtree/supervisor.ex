defmodule RegentsWeb.Techtree.Supervisor do
  @moduledoc """
  Techtree's web-layer runtime processes: tracks concurrent Wallet Bench
  evidence and zip downloads on this machine (`RegentsWeb.Techtree.ResultsDownloads`).
  Started by `Regents.Application` where pages are served.
  """

  use Supervisor

  def start_link(_opts), do: Supervisor.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    Supervisor.init(
      [
        {Registry, keys: :duplicate, name: RegentsWeb.Techtree.ResultsDownloads}
      ],
      strategy: :one_for_one
    )
  end
end
