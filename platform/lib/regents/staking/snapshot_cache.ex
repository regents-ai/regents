defmodule Regents.Staking.SnapshotCache do
  @moduledoc """
  The last successful public staking reading, shared through Postgres.

  Pages buy no chain reads. Refreshes use one unique Oban job across the site's
  machines; Oban owns scheduling and retries. A failure leaves the saved reading
  and its original block/time untouched. Wallet balances are never stored here.
  """

  alias Regents.Staking
  alias Regents.Staking.{Facts, SnapshotRefresh}
  alias Regents.WalletActions.Abi

  @topic "staking:protocol_snapshot"
  @minimum_interval 10
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

  def refresh(notify \\ self()) when is_pid(notify) do
    if remaining_delay(snapshot()) > 0,
      do: {:error, :refresh_too_soon},
      else: enqueue(0)
  end

  # Confirmation may arrive just after a reading. Oban schedules the next one
  # when it is allowed; this never delays or deduplicates a wallet action.
  def refresh_soon, do: enqueue(remaining_delay(snapshot()))

  def remaining_delay(nil), do: 0

  def remaining_delay(%{read_at: read_at}) do
    max(@minimum_interval - DateTime.diff(DateTime.utc_now(), read_at, :second), 0)
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
