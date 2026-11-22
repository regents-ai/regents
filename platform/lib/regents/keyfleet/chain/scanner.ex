defmodule Regents.Keyfleet.Chain.Scanner do
  @moduledoc """
  One pass over a deployed fleet's history: who holds each of its Keys and
  each Key's reveal, from the Key collection every fleet shares; what it
  forwarded to its treasury or sent as the protocol share, from its manager;
  its proposals, votes, cancellations and executions, which Keys' workspace
  edits a proposal restricted, and each Key's presence, from its vote
  contract; the shards its Keys' owners issued and ended and whether those
  shards may vote, from the shard record every fleet shares; what its
  treasury paid, advanced, got back and split, from its treasury; rewards
  settled and paid out, from its reward ledger; and its USDC from Key sales
  turned into REGENT, from the REGENT buyer every fleet shares, the one its
  manager names at the head the pass reads.

  Each pass reads the head and the buyer the manager names there, and a pass
  that cannot read the buyer reads nothing and fails. It then reads again the
  last 300 blocks it already
  recorded (about a minute of Base at five blocks a second), then records what
  happened after them up to the head. Each stretch of blocks is one request
  for all seven contracts, and its records are made in the order the chain made
  them. A stretch the node will not answer
  whole, such as one whose logs are more than it sends at once, is asked for
  again in halves, down to single blocks, and each answered piece is recorded
  before the next is asked for, so a pass holds one answer at most.

  A piece read for the first time is recorded in one transaction with the
  fleet's cursor moved past it, so the cursor always stands just after the
  last piece recorded. Every piece, in the second reading too, is compared
  with what is saved and recorded while the cursor is held where the pass
  left it; if another pass has moved it, the piece is rolled back and the
  pass ends quietly, leaving the cursor where it now stands. The first piece
  that cannot be read ends the pass with the cursor there, and the next pass
  carries on from it: a single block the node will not answer, which is
  named in the error, or a piece with a malformed or unknown log, a proposal
  without its author key's renewal, a proposal number skipped, or a vote,
  cancellation or execution for a proposal not recorded yet. That piece
  records nothing. Recording is safe to repeat: a record read twice is made
  once and keeps its number. Nothing above the head this pass read is asked
  for, so a node that is behind reads as a shorter pass, never as missing
  history.

  Every record is kept as first saved. Each piece is compared with what is
  saved, transaction by transaction, before anything in it is recorded. The
  logs of a transaction with nothing saved yet are new history and are
  recorded; a transaction already saved records nothing more, wherever the
  chain now puts it. A new record that would take the place of one kept, such
  as another owner for an ownership epoch, another reveal of a key or another
  proposal under a number, is not made. A saved transaction whose logs no
  longer match its records, because it moved to another block, its block's
  hash changed, a log changed or it is gone, keeps its records and is named
  in one warning, with its contracts, by the pass that reads its block for
  the last time: the one that moves the cursor more than 300 blocks past it.

  A pass that made a new proposal or money record says so on
  `Regents.Keyfleet.Proposals.topic/1`. One that recorded keys revealed, sold,
  changing hands, issuing or ending shards, turning their agent voting on or
  off, or having their edits restricted or allowed names them all in one
  notice on `Regents.Keyfleet.Keys.topic/1`, wherever in the pass it recorded them. Keys
  marked present in the blocks it read for the first time are named in one
  notice of their own there, `{:keys_present, fleet_id, token_ids}`, however
  many marks they came in, so a page reads again only what shows presence.
  Each is said even if the pass then failed, and each is only a hint to read
  again.
  """

  require Logger

  alias RegentChain.Abi
  alias RegentChain.Call
  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.Chain
  alias Regents.Keyfleet.Chain.Logs
  alias Regents.Keyfleet.Chain.MoneyLog
  alias Regents.Keyfleet.Chain.RpcClient
  alias Regents.Keyfleet.Fleets.Fleet
  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.Proposals
  alias Regents.Keyfleet.Treasury

  @rescan_blocks 300
  @regent_buyer Call.encode("REGENT_BUYER()", [])
  @max_range 10_000
  @system %System{}

  @doc """
  Runs one pass with the site's node (`Regents.Keyfleet.Chain.RpcClient`).

  Returns `:ok` once the cursor has reached the end of the pass, `:moved`
  when someone else moved the cursor during the pass, and `{:error, reason}`
  when the chain could not be read, in which case the cursor stands just
  after the last piece recorded.
  """
  def step(%Fleet{} = fleet) do
    cursor =
      Chain.get_cursor!(fleet.id) ||
        Chain.open_cursor!(%{fleet_id: fleet.id, next_block: fleet.deployed_block},
          actor: @system
        )

    result =
      with {:ok, head} <- RpcClient.head(),
           {:ok, buyer} <- regent_buyer(fleet, head),
           contracts = {fleet, buyer},
           {:ok, pass} <- reread(contracts, %{cursor: cursor, differs: []}, head),
           {:ok, _pass} <- read_forward(contracts, pass, head) do
        :ok
      else
        {:moved, from_block} -> moved(fleet, from_block)
        {:error, reason} -> {:error, reason}
      end

    announce(cursor)
    result
  end

  defp advance(next_block, head) do
    %{
      next_block: next_block,
      head_block: head.number,
      head_block_hash: head.hash,
      observed_at: DateTime.utc_now()
    }
  end

  # The REGENT buyer the fleet's manager names, which never changes.
  defp regent_buyer(fleet, head) do
    with {:ok, returned} <- RpcClient.call(fleet.manager_address, @regent_buyer, head.hash),
         {:ok, [buyer]} <- Abi.decode(returned, [:address]) do
      {:ok, buyer}
    else
      {:error, reason} -> {:error, {:regent_buyer_unread, reason}}
      :error -> {:error, {:regent_buyer_unread, :unreadable_answer}}
    end
  end

  # The last 300 blocks recorded, each piece held where the cursor stands.
  defp reread({fleet, _buyer} = contracts, pass, head) do
    from = max(fleet.deployed_block, pass.cursor.next_block - @rescan_blocks)
    to = min(pass.cursor.next_block - 1, head.number)

    each_piece(contracts, from, to, pass, fn from, to, records, pass ->
      write_piece(contracts, {from, to, records}, pass, &{:ok, &1})
    end)
  end

  # Each piece moves the cursor past itself as it is recorded.
  defp read_forward(contracts, pass, head) do
    from = pass.cursor.next_block
    to = min(head.number, from + @max_range - 1)

    if to < from do
      with {:ok, cursor} <-
             write_cursor(pass.cursor, &Chain.advance_cursor(&1, advance(from, head))),
           do: {:ok, %{pass | cursor: cursor}}
    else
      each_piece(contracts, from, to, pass, fn from, to, records, pass ->
        write_piece(
          contracts,
          {from, to, records},
          pass,
          &Chain.advance_cursor(&1, advance(to + 1, head))
        )
      end)
    end
  end

  # Reads `from..to` in chain order. A stretch the node will not answer whole
  # is asked for again in halves, and each answered piece goes to `handle`
  # before the next is asked for, so a pass holds one answer at most. The
  # first piece that fails ends the reading, and so does a node asking for
  # fewer requests (HTTP 429): halves would only ask it more.
  defp each_piece(_contracts, from, to, acc, _handle) when to < from, do: {:ok, acc}

  defp each_piece({fleet, buyer} = contracts, from, to, acc, handle) do
    case RpcClient.get_logs(Logs.addresses(fleet, buyer), Logs.topics(), from, to) do
      {:ok, logs} ->
        with {:ok, records} <- Logs.decode(logs, fleet, buyer, from, to),
             do: handle.(from, to, records, acc)

      {:error, :chain_busy} ->
        {:error, {:block_unanswered, from, :chain_busy}}

      {:error, _reason} when from < to ->
        middle = div(from + to, 2)

        with {:ok, acc} <- each_piece(contracts, from, middle, acc, handle),
             do: each_piece(contracts, middle + 1, to, acc, handle)

      {:error, reason} ->
        {:error, {:block_unanswered, from, reason}}
    end
  end

  # A piece is compared with what is saved, its new records are made, and
  # `to_cursor` holds or moves the cursor after them, together or not at all,
  # with the cursor held from the start so no other pass records anything in
  # between. It is refused, and the piece rolled back, once the cursor no
  # longer stands where this pass left it. A record the database refuses ends
  # the transaction there and comes back as its changeset.
  defp write_piece({fleet, _buyer} = contracts, {from, to, records}, pass, to_cursor) do
    Regents.Repo.transact(fn ->
      with {:ok, _held} <- write_cursor(pass.cursor, &Chain.hold_cursor/1),
           saved = saved(fleet.id, from, to, records),
           {fresh, differs} = compare(contracts, records, saved, from..to//1),
           :ok <- record(fleet, fresh),
           {:ok, cursor} <- write_cursor(pass.cursor, to_cursor) do
        {:ok, %{cursor: cursor, differs: pass.differs ++ differs}}
      else
        failure -> {:error, failure}
      end
    end)
    |> case do
      {:ok, pass} ->
        {:ok, settle(fleet, pass)}

      {:error, %Ash.Changeset{} = refused} ->
        {:error, Ash.Error.to_error_class(refused.errors)}

      {:error, failure} ->
        failure
    end
  end

  # `to_cursor` writes from the cursor as this pass last left it.
  defp write_cursor(cursor, to_cursor) do
    case to_cursor.(cursor) do
      {:ok, cursor} -> {:ok, cursor}
      {:error, :moved} -> {:moved, cursor.next_block}
      {:error, error} -> {:error, error}
    end
  end

  # Everything saved from blocks `from..to` of the fleet, and from the
  # transactions of `records` wherever it was saved.
  defp saved(fleet_id, from, to, records) do
    transactions = records |> Enum.map(fn {_type, fields} -> fields.transaction_hash end)
    named = %{transactions: Enum.uniq(transactions)}

    Enum.concat([
      Keys.recorded_in_blocks!(fleet_id, from, to, named, actor: @system),
      Keys.reveals_in_blocks!(fleet_id, from, to, named, actor: @system),
      Keys.reveal_expiries_in_blocks!(fleet_id, from, to, named, actor: @system),
      Keys.shard_events_in_blocks!(fleet_id, from, to, named, actor: @system),
      Keys.edits_restrictions_in_blocks!(fleet_id, from, to, named, actor: @system),
      Keys.agent_voting_in_blocks!(fleet_id, from, to, named, actor: @system),
      Keys.presences_in_blocks!(fleet_id, from, to, named, actor: @system),
      Proposals.recorded_in_blocks!(fleet_id, from, to, named.transactions),
      Treasury.recorded_in_blocks!(fleet_id, from, to, named.transactions)
    ])
  end

  # The records read of transactions with nothing saved yet, and each saved
  # transaction from `blocks` whose logs read now no longer match its
  # records. A transaction's logs are all in one block.
  defp compare(contracts, records, saved, blocks) do
    saved = Enum.group_by(saved, & &1.transaction_hash)
    read = Enum.group_by(records, fn {_type, fields} -> fields.transaction_hash end)

    fresh =
      Enum.reject(records, fn {_type, fields} ->
        Map.has_key?(saved, fields.transaction_hash)
      end)

    differs =
      for {transaction, [%{block_number: block} | _rest] = rows} <- saved,
          block in blocks,
          not same?(rows, Map.get(read, transaction, [])),
          do: %{
            block: block,
            transaction: transaction,
            contracts: rows |> Enum.map(&contract(contracts, &1)) |> Enum.uniq()
          }

    {fresh, differs}
  end

  # A record of the same kind read now at each saved record's log index, and
  # no other, with every field the log gives the same, its block and block
  # hash among them.
  defp same?(rows, read) do
    read = Map.new(read, fn {_type, fields} = record -> {fields.log_index, record} end)

    map_size(read) == length(rows) and
      Enum.all?(rows, fn row ->
        case Map.fetch(read, row.log_index) do
          {:ok, {type, fields}} ->
            type == kind(row) and Enum.all?(fields, &same_field?(row, &1))

          :error ->
            false
        end
      end)
  end

  # A field read now, cast as the record's attribute is; a proposal number
  # against the number of the proposal the record names.
  defp same_field?(%resource{} = row, {field, read}) do
    saved = Map.fetch!(row, field)

    case Ash.Resource.Info.attribute(resource, field) do
      nil ->
        saved == read

      %{type: type, constraints: constraints} ->
        case Ash.Type.cast_input(type, read, constraints) do
          {:ok, cast} -> Ash.Type.equal?(type, saved, cast, constraints)
          _uncast -> false
        end
    end
  end

  defp kind(%Keys.KeyAttachment{}), do: :ownership
  defp kind(%Keys.KeyReveal{}), do: :reveal
  defp kind(%Keys.KeyRevealExpiry{}), do: :reveal_expiry
  defp kind(%Keys.ShardEvent{}), do: :shard
  defp kind(%Keys.EditsRestriction{}), do: :edits_restriction
  defp kind(%Keys.AgentVoting{}), do: :agent_voting
  defp kind(%Keys.Presence{}), do: :presence
  defp kind(%Proposals.Proposal{}), do: :proposal
  defp kind(%Proposals.Vote{}), do: :ballot
  defp kind(%Proposals.Cancellation{}), do: :cancellation
  defp kind(%Proposals.Execution{}), do: :execution
  defp kind(%Treasury.Event{}), do: :treasury_event

  # The contract whose log a record was made from.
  defp contract({fleet, buyer}, %Treasury.Event{kind: kind}) do
    case MoneyLog.contract(kind) do
      :fleet -> fleet.manager_address
      :treasury -> fleet.treasury_address
      :rewards -> fleet.rewards_address
      :buyer -> buyer
    end
  end

  defp contract({fleet, _buyer}, row) do
    case kind(row) do
      kind when kind in [:ownership, :reveal, :reveal_expiry] -> fleet.keys_address
      kind when kind in [:shard, :agent_voting] -> fleet.shards_address
      _votes -> fleet.votes_address
    end
  end

  # Each saved transaction found no longer matching the chain is named once,
  # by the pass that reads its block for the last time: once the cursor stands
  # more than 300 blocks past it, no later pass reads it again. The rest are
  # found again by this pass's next piece or the next pass.
  defp settle(fleet, %{cursor: cursor, differs: differs} = pass) do
    {last, later} = Enum.split_with(differs, &(&1.block < cursor.next_block - @rescan_blocks))

    for %{transaction: transaction, contracts: contracts} <- last do
      Logger.warning(
        "Fleet #{fleet.id}: transaction #{transaction} on #{Enum.join(contracts, ", ")} " <>
          "no longer matches the chain; the records saved first are kept."
      )
    end

    %{pass | differs: later}
  end

  # Each new proposal must be the fleet's next number, and each ballot,
  # cancellation and execution must name a proposal recorded by then.
  defp record(fleet, records) do
    with :ok <- Logs.in_sequence(records, Proposals.highest_number!(fleet.id)),
         do: Enum.reduce_while(records, :ok, &record_one/2)
  end

  defp record_one(record, :ok) do
    case make_record(record) do
      {:ok, _recorded} -> {:cont, :ok}
      {:error, error} -> {:halt, {:error, error}}
    end
  end

  # A refused record is returned rather than rolling back the piece's
  # transaction, which `write_piece/4` undoes as a whole.
  @record_opts [actor: @system, rollback_on_error?: false]

  defp make_record({:ownership, epoch}), do: Keys.record_epoch(epoch, @record_opts)
  defp make_record({:reveal, reveal}), do: Keys.record_reveal(reveal, @record_opts)
  defp make_record({:reveal_expiry, expiry}), do: Keys.record_reveal_expiry(expiry, @record_opts)

  defp make_record({:proposal, proposal}), do: Proposals.record_proposal(proposal, @record_opts)
  defp make_record({:ballot, vote}), do: Proposals.record_vote(vote, @record_opts)

  defp make_record({:cancellation, cancellation}),
    do: Proposals.record_cancellation(cancellation, @record_opts)

  defp make_record({:execution, execution}),
    do: Proposals.record_execution(execution, @record_opts)

  defp make_record({:edits_restriction, restriction}),
    do: Keys.record_edits_restriction(restriction, @record_opts)

  defp make_record({:shard, event}), do: Keys.record_shard_event(event, @record_opts)
  defp make_record({:agent_voting, setting}), do: Keys.record_agent_voting(setting, @record_opts)
  defp make_record({:presence, presence}), do: Keys.record_presence(presence, @record_opts)
  defp make_record({:treasury_event, event}), do: Treasury.record_event(event, @record_opts)

  # The cursor as the pass found it; the records it made moved its numbers on.
  # Every key revealed or whose draw's wait was ended, sold, changing hands,
  # issuing or ending a shard, turning its agent voting on or off, or having
  # its edits restricted or allowed in the pass is named once, and so is every
  # key marked present in the blocks the pass moved the cursor past.
  defp announce(%{fleet_id: fleet_id} = before) do
    now = Chain.get_cursor!(fleet_id)

    present =
      since(now.next_block, before.next_block, fn ->
        for(
          %{kind: :present, token_id: token_id} <-
            Keys.presences_in_blocks!(fleet_id, before.next_block, now.next_block - 1,
              actor: @system
            ),
          uniq: true,
          do: token_id
        )
      end)

    revealed =
      since(now.reveal_seq, before.reveal_seq, fn ->
        Keys.reveals_recorded_since!(fleet_id, before.reveal_seq, actor: @system) ++
          Keys.reveal_expiries_recorded_since!(fleet_id, before.reveal_seq, actor: @system)
      end)

    owned =
      since(now.ownership_seq, before.ownership_seq, fn ->
        Keys.epochs_recorded_since!(fleet_id, before.ownership_seq, actor: @system)
      end)

    sharded =
      since(now.shard_seq, before.shard_seq, fn ->
        Keys.shard_events_recorded_since!(fleet_id, before.shard_seq, actor: @system) ++
          Keys.agent_voting_recorded_since!(fleet_id, before.shard_seq, actor: @system)
      end)

    restricted =
      since(now.proposal_seq, before.proposal_seq, fn ->
        Keys.edits_restrictions_recorded_since!(fleet_id, before.proposal_seq, actor: @system)
      end)

    if now.proposal_seq > before.proposal_seq do
      Phoenix.PubSub.broadcast(
        Regents.PubSub,
        Proposals.topic(fleet_id),
        {:proposals_changed, fleet_id}
      )
    end

    case Enum.uniq_by(revealed ++ owned ++ sharded ++ restricted, & &1.token_id) do
      [] ->
        :ok

      records ->
        # Whoever was let into the fleet's code or notebooks is checked afresh.
        Regents.Keyfleet.Code.end_access(fleet_id)
        Regents.Keyfleet.Notebooks.end_access(fleet_id)

        Phoenix.PubSub.broadcast(
          Regents.PubSub,
          Keys.topic(fleet_id),
          {:keys_changed, fleet_id, Enum.map(records, & &1.token_id)}
        )
    end

    if present != [] do
      Phoenix.PubSub.broadcast(
        Regents.PubSub,
        Keys.topic(fleet_id),
        {:keys_present, fleet_id, present}
      )
    end
  end

  # The rows a pass recorded under one of the cursor's numbers, read only when
  # the pass moved that number on.
  defp since(now, before, read) when now > before, do: read.()
  defp since(_now, _before, _read), do: []

  # Another pass moved the cursor during this one. The pass leaves the cursor
  # as it is, and the next pass reads on from wherever it then stands.
  defp moved(fleet, from_block) do
    Logger.info(
      "Fleet #{fleet.id}: the cursor moved underneath a pass that left it at block " <>
        "#{from_block}; the pass ended and wrote nothing more."
    )

    :moved
  end
end
