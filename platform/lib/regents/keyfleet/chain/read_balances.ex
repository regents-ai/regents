defmodule Regents.Keyfleet.Chain.ReadBalances do
  @moduledoc """
  One `Regents.Keyfleet.Chain.TreasuryReader` reading of a deployed fleet's
  balances, queued every five minutes by `Regents.Keyfleet.Chain.Watch`, apart from
  the reading of its history, so a slow read never holds that up, and at once
  when a step sent from a page lands (`Regents.Keyfleet.Chain.Watch.refresh/1`) or
  someone presses the Treasury's refresh (`now/1`). A reading that fails is
  logged and tried again a few times; the next turn's reading follows either
  way.

  Only one reading of a fleet waits to start at a time; one asked for while
  another is under way waits to read a later block, and the reading kept is
  always the latest block's (`Regents.Keyfleet.Treasury.Reading`).
  """
  use Oban.Worker,
    queue: :keyfleet_chain,
    max_attempts: 3,
    unique: [keys: [:fleet_id], period: :infinity, states: [:available, :scheduled]]

  require Logger

  alias Regents.Keyfleet.Chain.TreasuryReader
  alias Regents.Keyfleet.Fleets

  @doc "Queues a reading of `fleet_id`'s balances now, unless one is already waiting."
  def now(fleet_id), do: %{fleet_id: fleet_id} |> new() |> Oban.insert!()

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"fleet_id" => fleet_id}}) do
    with %{manager_address: address} = fleet when is_binary(address) <-
           Fleets.get_fleet!(fleet_id),
         {:error, reason} <- TreasuryReader.read(fleet) do
      Logger.warning("Fleet #{fleet_id}: reading its balances failed: #{inspect(reason)}")
      {:error, reason}
    else
      {:ok, _reading} -> :ok
      _not_deployed -> {:cancel, :not_deployed}
    end
  end
end
