defmodule Regents.Staking.SnapshotRefresh do
  @moduledoc "The site's one restart-safe, incremental staking refresh."

  use Oban.Worker,
    queue: :staking_reads,
    max_attempts: 3,
    unique: [fields: [:worker], period: :infinity, states: :incomplete]

  alias Regents.Actors.System
  alias Regents.Staking
  alias Regents.Staking.{ChainClient, PriceClient, SnapshotCache}

  @impl Oban.Worker
  def timeout(_job), do: 70_000

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    result = refresh()

    case result do
      {:ok, _snapshot} ->
        # Every machine receives this committed reading, even without an
        # Erlang cluster. Listeners read the row and notify their local pages.
        SnapshotCache.announce(:updated)

      {:snooze, seconds} ->
        {:snooze, seconds}

      {:error, _reason} = error ->
        SnapshotCache.announce(:unavailable)
        error
    end
  end

  defp refresh do
    with {:ok, previous} <- Staking.get_protocol_reading(SnapshotCache.key(), actor: %System{}) do
      snapshot = if previous, do: SnapshotCache.decode(previous.snapshot)

      case SnapshotCache.remaining_delay(snapshot) do
        0 -> read_and_save(previous, snapshot)
        seconds -> {:snooze, seconds}
      end
    end
  end

  defp read_and_save(previous, snapshot) do
    history = if previous, do: previous.history

    with {:ok, protocol, history} <- ChainClient.module().protocol_snapshot(history),
         protocol = Map.merge(protocol, quote_values(snapshot)),
         {:ok, saved} <- save(previous, protocol, history) do
      :telemetry.execute(
        [:regents, :staking, :refresh],
        %{history_blocks: protocol.block_number - history_start(previous, protocol) + 1},
        %{chain_id: 8453, bootstrap: is_nil(previous)}
      )

      {:ok, SnapshotCache.decode(saved.snapshot)}
    end
  end

  defp save(nil, snapshot, history),
    do:
      Staking.record_protocol_reading(
        %{id: SnapshotCache.key(), snapshot: json(snapshot), history: history},
        actor: %System{}
      )

  defp save(previous, snapshot, history),
    do:
      Staking.replace_protocol_reading(previous, %{snapshot: json(snapshot), history: history},
        actor: %System{}
      )

  defp json(snapshot), do: snapshot |> Jason.encode!() |> Jason.decode!()

  defp quote_values(previous) do
    old =
      if previous,
        do: Map.take(previous, [:regent_price_usd, :regent_price_read_at]),
        else: %{regent_price_usd: :unavailable, regent_price_read_at: nil}

    read_at = old.regent_price_read_at

    if is_nil(read_at) || DateTime.diff(DateTime.utc_now(), read_at, :second) >= 120 do
      case PriceClient.quote() do
        {:ok, price} when is_binary(price) and price != "" ->
          %{regent_price_usd: price, regent_price_read_at: DateTime.utc_now()}

        _unavailable ->
          old
      end
    else
      old
    end
  end

  defp history_start(nil, protocol), do: protocol.usdc_received_from_block

  defp history_start(previous, protocol),
    do: max(protocol.usdc_received_from_block, previous.history["block_number"] - 29)
end
