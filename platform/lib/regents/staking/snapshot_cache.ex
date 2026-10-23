defmodule Regents.Staking.SnapshotCache do
  @moduledoc """
  The last successful public staking reading, shared through Postgres.

  Pages buy no chain reads. Refreshes use one unique Oban job across the site's
  machines, every five minutes and early when `Regents.ChainRefresh` asks; Oban
  owns scheduling and retries. A failure leaves the saved reading and its
  original block/time untouched. Wallet balances are never stored here.
  """

  @behaviour Regents.ChainRefresh

  alias Regents.{ChainRefresh, Staking}
  alias Regents.Staking.{Facts, SnapshotRefresh}
  alias Regents.WalletActions.Abi

  @topic "staking:protocol_snapshot"
  @dates [:read_at, :regent_price_read_at, :clanker_vault_locked_until, :clanker_vault_vested_by]

  def topic, do: @topic
  def channel, do: "regents_staking_snapshot_v1"
  def key, do: "regents:staking:v1:8453:#{Abi.normalize_address!(Abi.staking_address())}"

  def announce(status) when status in [:updated, :unavailable] do
    case Ecto.Adapters.SQL.query(Regents.Repo, "SELECT pg_notify($1, $2)", [
           channel(),
           to_string(status)
         ]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def snapshot do
    if Application.get_env(:regents, :database_startup_enabled, false) do
      case Staking.current_protocol_reading(key()) do
        {:ok, %{snapshot: snapshot}} -> decode(snapshot)
        _unavailable -> nil
      end
    end
  end

  @doc """
  Reads the staking contract on Base again: at once, or ten seconds after the
  last reading. This never delays or deduplicates a wallet action; it only
  follows one.
  """
  @impl ChainRefresh
  def refresh(8453), do: enqueue(remaining_delay(snapshot()))
  def refresh(_chain_id), do: :ok

  def remaining_delay(nil), do: 0

  def remaining_delay(%{read_at: read_at}) do
    max(ChainRefresh.gap_s() - DateTime.diff(DateTime.utc_now(), read_at, :second), 0)
  end

  defp enqueue(delay) do
    if Application.get_env(:regents, :database_startup_enabled, false) do
      case %{key: key()} |> SnapshotRefresh.new(schedule_in: delay) |> Oban.insert() do
        {:ok, _job} -> :ok
        {:error, _reason} -> {:error, :unavailable}
      end
    else
      {:error, :unavailable}
    end
  end

  # JSON keys come only from the fixed protocol vocabulary; no data creates atoms.
  def decode(snapshot) do
    Map.new(Facts.protocol_keys(), fn key ->
      value = Map.get(snapshot, Atom.to_string(key))

      value =
        cond do
          value == "unavailable" -> :unavailable
          key in @dates && is_binary(value) -> value |> DateTime.from_iso8601() |> datetime()
          true -> value
        end

      {key, value}
    end)
  end

  defp datetime({:ok, value, _offset}), do: value
end
