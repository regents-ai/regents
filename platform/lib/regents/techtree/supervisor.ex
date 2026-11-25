defmodule Regents.Techtree.Supervisor do
  @moduledoc """
  Techtree's core runtime processes: currently the kept Wallet Bench reading
  (`Regents.Techtree.WalletBench.Reading`), refreshed at most every 30 seconds
  and shared across the Wallet Bench page, Markdown view, JSON feed, and hosted
  MCP tool.
  """

  use Supervisor

  def start_link(_opts), do: Supervisor.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    Supervisor.init(
      [
        Regents.Techtree.WalletBench.Reading
      ],
      strategy: :one_for_one
    )
  end
end
