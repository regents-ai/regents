defmodule Regents.Keyfleet.Chain do
  @moduledoc """
  What the site knows about each fleet from its contracts: how far its key
  and proposal history has been read, whether that reading is fresh enough to
  act on, and how far the fleet has sold.
  """
  use Ash.Domain

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.Chain.Cursor
  alias Regents.Keyfleet.Fleets.Presets
  alias Regents.Keyfleet.Keys.KeyAttachment

  resources do
    resource Regents.Keyfleet.Chain.Cursor do
      define :open_cursor, action: :open
      define :fresh_cursor, action: :fresh, args: [:fleet_id], not_found_error?: false
      define :get_cursor, action: :read, get_by: [:fleet_id], not_found_error?: false
    end
  end

  @doc """
  Whether the fleet's key ownership was read recently enough to act on.

  Anything that grants authority from holding a key asks this first and
  refuses when the answer is no. Reading pages never does.
  """
  def fresh?(fleet_id), do: fresh_cursor!(fleet_id) != nil

  @doc "The fleet's sales so far and what its next key costs, in atomic USDC."
  def progress(fleet_id) do
    case minted(fleet_id) do
      {:ok, minted} -> Presets.progress(fleet_id, minted)
      {:error, failure} -> raise failure
    end
  end

  @doc """
  How many keys the fleet has sold, as far as its key history has been read:
  the highest key number read, since the contract numbers keys from 1 in the
  order it sells them and has no way to burn one.
  """
  def minted(fleet_id, opts \\ []) do
    KeyAttachment
    |> Ash.Query.for_read(:latest_in_fleet, %{fleet_id: fleet_id})
    |> Ash.read_one(opts)
    |> case do
      {:ok, nil} -> {:ok, 0}
      {:ok, latest} -> {:ok, latest.token_id}
      error -> error
    end
  end

  @doc """
  Takes the next number for one of the fleet's proposal or budget records. Called inside
  the transaction that makes the record, it holds the fleet's count until
  commit, so numbers are given in the order records are made and a record
  that rolls back gives its number back.
  """
  # The schema is the repository's own constant; every value is a parameter.
  # sobelow_skip ["SQL.Query"]
  def take_proposal_seq!(fleet_id) do
    %Postgrex.Result{rows: [[seq]]} =
      Regents.Repo.query!(
        "UPDATE #{Regents.Keyfleet.schema()}.chain_cursors SET proposal_seq = proposal_seq + 1 " <>
          "WHERE fleet_id = $1 RETURNING proposal_seq",
        [fleet_id]
      )

    seq
  end

  @doc "Takes the next number for one of the fleet's key reveals, as `take_proposal_seq!/1` does."
  # The schema is the repository's own constant; every value is a parameter.
  # sobelow_skip ["SQL.Query"]
  def take_reveal_seq!(fleet_id) do
    %Postgrex.Result{rows: [[seq]]} =
      Regents.Repo.query!(
        "UPDATE #{Regents.Keyfleet.schema()}.chain_cursors SET reveal_seq = reveal_seq + 1 " <>
          "WHERE fleet_id = $1 RETURNING reveal_seq",
        [fleet_id]
      )

    seq
  end

  @doc "Takes the next number for one of the fleet's ownership epochs, as `take_proposal_seq!/1` does."
  # The schema is the repository's own constant; every value is a parameter.
  # sobelow_skip ["SQL.Query"]
  def take_ownership_seq!(fleet_id) do
    %Postgrex.Result{rows: [[seq]]} =
      Regents.Repo.query!(
        "UPDATE #{Regents.Keyfleet.schema()}.chain_cursors SET ownership_seq = ownership_seq + 1 " <>
          "WHERE fleet_id = $1 RETURNING ownership_seq",
        [fleet_id]
      )

    seq
  end

  @doc "Takes the next number for one of the fleet's shards issued or ended, as `take_proposal_seq!/1` does."
  # The schema is the repository's own constant; every value is a parameter.
  # sobelow_skip ["SQL.Query"]
  def take_shard_seq!(fleet_id) do
    %Postgrex.Result{rows: [[seq]]} =
      Regents.Repo.query!(
        "UPDATE #{Regents.Keyfleet.schema()}.chain_cursors SET shard_seq = shard_seq + 1 " <>
          "WHERE fleet_id = $1 RETURNING shard_seq",
        [fleet_id]
      )

    seq
  end

  @doc """
  Moves the fleet's cursor as `changes` say, in one update that requires the
  stored cursor still to stand where `cursor` does. Returns `{:ok, cursor}`,
  `{:error, :moved}` when someone else has moved the cursor since, or
  `{:error, error}`.
  """
  def advance_cursor(%Cursor{} = cursor, changes) do
    cursor
    |> standing()
    |> Ash.bulk_update(:advance, changes,
      strategy: :atomic,
      return_records?: true,
      return_errors?: true,
      rollback_on_error?: false,
      actor: %System{}
    )
    |> case do
      %Ash.BulkResult{status: :success, records: [cursor]} -> {:ok, cursor}
      %Ash.BulkResult{status: :success, records: []} -> {:error, :moved}
      %Ash.BulkResult{errors: errors} -> {:error, Ash.Error.to_error_class(errors)}
    end
  end

  @doc """
  Locks the fleet's cursor until the current transaction ends, if it still
  stands where `cursor` does. Returns `{:ok, cursor}` or `{:error, :moved}`.
  """
  def hold_cursor(%Cursor{} = cursor) do
    cursor
    |> standing()
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!()
    |> case do
      nil -> {:error, :moved}
      cursor -> {:ok, cursor}
    end
  end

  defp standing(cursor) do
    Ash.Query.for_read(Cursor, :standing, %{
      fleet_id: cursor.fleet_id,
      next_block: cursor.next_block
    })
  end
end
