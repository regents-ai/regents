defmodule Regents.Keyfleet.Proposals do
  @moduledoc """
  A fleet's proposals, the votes cast on them, their cancellations and their
  executions, recorded from its vote contract by the chain reader and by
  nothing else. The chain
  is the authority; these records only mirror it. Anyone may read them.

  A proposal's words are kept here too, saved by whoever proposes and shown
  only with the proposal whose fingerprint they match
  (`Regents.Keyfleet.Proposals.Words`).
  """
  use Ash.Domain

  require Ash.Query

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.Chain
  alias Regents.Keyfleet.Keys.EditsRestriction
  alias Regents.Keyfleet.Proposals.{Cancellation, Execution, Proposal, Vote}
  alias Regents.Keyfleet.Treasury.Event
  alias Regents.Keyfleet.WalletSteps.Typed

  @page 20
  @changes_page 50
  # What a proposal is shown with: its tally, its words, and its
  # cancellation or execution.
  @summary [:yes_keys, :no_keys, :abstain_keys, :late_keys, :words, :cancellation, :execution]

  resources do
    resource Regents.Keyfleet.Proposals.Proposal do
      define :record_proposal, action: :record
      define :get_proposal, action: :read, get_by: [:fleet_id, :number], not_found_error?: false

      define :latest_proposal,
        action: :latest_in_fleet,
        args: [:fleet_id],
        not_found_error?: false

      define :proposals_recorded_in_blocks,
        action: :recorded_in_blocks,
        args: [:fleet_id, :from_block, :to_block]

      define :proposals_recorded_before,
        action: :recorded_before,
        args: [:fleet_id, :before_seq, :limit]

      define :proposals_opened_before,
        action: :opened_before,
        args: [:fleet_id, :before_at, :before_id, :limit]

      define :proposals_closed_before,
        action: :closed_before,
        args: [:fleet_id, :before_at, :before_id, :limit]
    end

    resource Regents.Keyfleet.Proposals.Words do
      define :write_words, action: :write, args: [:fleet_id, :text]
    end

    resource Regents.Keyfleet.Proposals.Vote do
      define :record_vote, action: :record

      define :votes_recorded_in_blocks,
        action: :recorded_in_blocks,
        args: [:fleet_id, :from_block, :to_block]

      define :votes_recorded_before,
        action: :recorded_before,
        args: [:fleet_id, :before_seq, :limit]
    end

    resource Regents.Keyfleet.Proposals.Cancellation do
      define :record_cancellation, action: :record

      define :cancellations_recorded_in_blocks,
        action: :recorded_in_blocks,
        args: [:fleet_id, :from_block, :to_block]

      define :cancellations_recorded_before,
        action: :recorded_before,
        args: [:fleet_id, :before_seq, :limit]
    end

    resource Regents.Keyfleet.Proposals.Execution do
      define :record_execution, action: :record

      define :executions_recorded_in_blocks,
        action: :recorded_in_blocks,
        args: [:fleet_id, :from_block, :to_block]

      define :executions_recorded_before,
        action: :recorded_before,
        args: [:fleet_id, :before_seq, :limit]
    end
  end

  @doc """
  Saves the words typed for a proposal of `fleet_id`, as its steps read them
  (`Regents.Keyfleet.WalletSteps.Typed.text/3`), so they match the fingerprint the
  proposal carries. Words that can't be a proposal's are not saved.
  """
  def save_words(fleet_id, typed, actor) do
    with {:ok, text} <- Typed.text(typed, :text, 4_000),
         do: write_words(fleet_id, text, actor: actor)
  end

  @doc "Where the reader says a fleet's proposal records may have changed."
  def topic(fleet_id), do: "keyfleet:fleet:#{fleet_id}:proposals"

  @doc """
  Where a proposal stands at `now`, as far as the fleet's history has been
  read, loaded with `#{inspect(@summary)}`. These are the contract's own
  states (`KeyfleetVotes.status`):

    * `:cancelled` and `:executed` once that is recorded;
    * `:open` until it closes;
    * then `:rejected` unless at least `approvals_needed/1` of the Keys
      present when it opened and the Keys that voted late voted yes;
    * otherwise `:waiting` until it can be carried out
      (`carry_out_from/1`), then `:approved` until its execution expiry, and
      `:execution_expired` from then on.
  """
  def status(%Proposal{} = proposal, now \\ DateTime.utc_now()) do
    cond do
      proposal.cancellation ->
        :cancelled

      proposal.execution ->
        :executed

      DateTime.before?(now, proposal.closes_at) ->
        :open

      proposal.yes_keys < approvals_needed(proposal.opening_count + proposal.late_keys) ->
        :rejected

      DateTime.before?(now, carry_out_from(proposal)) ->
        :waiting

      DateTime.compare(now, proposal.execution_expiry) != :lt ->
        :execution_expired

      true ->
        :approved
    end
  end

  @doc "How long every proposal is open to votes, in hours. The one place it is set."
  def vote_hours, do: 24

  @doc """
  When an approved proposal can first be carried out: 48 hours before its
  execution expiry, as the vote contract recorded it. A proposal that moves
  money waits a day after voting closes; any other can be carried out as soon
  as voting closes.
  """
  def carry_out_from(%Proposal{execution_expiry: expiry}), do: DateTime.add(expiry, -48, :hour)

  @doc "Whether a proposal waits after voting closes before it can be carried out."
  def waits?(%Proposal{closes_at: closes_at} = proposal),
    do: DateTime.after?(carry_out_from(proposal), closes_at)

  @doc """
  How many Yes votes approve a proposal `voters` Keys may vote on: 60% of
  them, rounded up, as `KeyfleetVotes.approvalsNeeded` counts. One present
  Key can approve a proposal on its own.
  """
  def approvals_needed(voters), do: div(voters * 60 + 99, 100)

  @doc "The fleet's proposal `number`, as `status/2` needs it, or nil."
  def get_by_number(fleet_id, number),
    do: get_proposal!(fleet_id, number, load: @summary)

  @doc """
  The fleet's proposals below `before_number` (all of them for nil), newest
  first, #{@page} at most, as `status/2` needs them, and whether older ones remain.
  """
  def list_page(fleet_id, before_number \\ nil) do
    Proposal
    |> Ash.Query.filter(fleet_id == ^fleet_id)
    |> below(before_number)
    |> Ash.Query.sort(number: :desc)
    |> Ash.Query.limit(@page + 1)
    |> Ash.Query.load(@summary)
    |> Ash.read!()
    |> Enum.split(@page)
    |> then(fn {proposals, older} -> {proposals, older != []} end)
  end

  @doc """
  The fleet's proposals a vote can still change at `now`, oldest first, as
  `status/2` needs them and with their votes: those still open, and those
  approved and waiting to be carried out.
  """
  def votable(fleet_id, now) do
    Proposal
    |> Ash.Query.filter(
      fleet_id == ^fleet_id and execution_expiry > ^DateTime.add(now, 48, :hour)
    )
    |> Ash.Query.sort(number: :asc)
    |> Ash.Query.load([:votes | @summary])
    |> Ash.read!()
    |> Enum.filter(&(status(&1, now) in [:open, :waiting]))
  end

  @doc "The Keys that have cast a ballot on proposal `number` of the fleet."
  def voted_keys(fleet_id, number) do
    Proposal
    |> Ash.Query.filter(fleet_id == ^fleet_id and number == ^number)
    |> Ash.Query.load(:votes)
    |> Ash.read_one!()
    |> case do
      nil -> []
      proposal -> Enum.flat_map(proposal.votes, & &1.token_ids)
    end
  end

  @doc "The fleet's proposals carried out, newest first, with their executions."
  def executed(fleet_id) do
    Proposal
    |> Ash.Query.filter(fleet_id == ^fleet_id and exists(execution, true))
    |> Ash.Query.sort(number: :desc)
    |> Ash.Query.load(:execution)
    |> Ash.read!()
  end

  @doc """
  The fleet's latest `count` proposals carried out, newest first, as
  `status/2` needs them.
  """
  def latest_carried_out(fleet_id, count) do
    Proposal
    |> Ash.Query.filter(fleet_id == ^fleet_id and exists(execution, true))
    |> Ash.Query.sort(number: :desc)
    |> Ash.Query.limit(count)
    |> Ash.Query.load(@summary)
    |> Ash.read!()
  end

  defp below(query, nil), do: query
  defp below(query, number), do: Ash.Query.filter(query, number < ^number)

  @doc """
  Each Key's vote on `proposal`, `%{yes: token_ids, no: token_ids, abstain:
  token_ids, silent: token_ids}`, each in token id order: the Keys whose latest
  vote is yes, no or abstain, and the Keys present when it opened that have not
  voted.
  """
  def key_ballots(proposal), do: Ash.load!(proposal, :key_ballots).key_ballots

  @doc """
  The votes on a proposal after its record number `after_seq`, oldest first,
  `limit` at most, and whether more remain.
  """
  def votes_after(proposal_id, after_seq, limit) do
    Vote
    |> Ash.Query.filter(proposal_id == ^proposal_id and record_seq > ^after_seq)
    |> Ash.Query.sort(record_seq: :asc)
    |> Ash.Query.limit(limit + 1)
    |> Ash.Query.load(:key_count)
    |> Ash.read!()
    |> Enum.split(limit)
    |> then(fn {votes, rest} -> {votes, rest != []} end)
  end

  @doc """
  What changed in the fleet's proposals after its record number `after_seq`.

  The first #{@changes_page} records after it, of every kind the reader numbers,
  are read. `items` holds each proposal they touch, as it stands now, with
  `changed_seq`, the last of them that touched it, and in that order.
  `next_cursor` is the last record read, to send as `after_seq` next time, or
  with none read `after_seq`, never past `head_seq`; `head_seq` is the fleet's
  last record number, and `has_more` whether records after `next_cursor` are
  waiting. Money records and a key's edits being
  restricted or allowed are counted but touch no proposal; the execution that
  restricted or allowed them does.
  """
  def changes(fleet_id, after_seq) do
    # The head is read first and bounds every query: a record numbered after
    # it may be saved between the queries below, and reading it from one kind
    # but not from another would move the next cursor past the one missed.
    cursor = Chain.get_cursor!(fleet_id)
    head_seq = if(cursor, do: cursor.proposal_seq, else: 0)

    {read, rest} =
      [Proposal, Vote, Cancellation, Execution, EditsRestriction, Event]
      |> Enum.flat_map(&records_after(&1, fleet_id, after_seq, head_seq))
      |> Enum.sort()
      |> Enum.split(@changes_page)

    changed = for {seq, proposal_id} <- read, proposal_id, into: %{}, do: {proposal_id, seq}

    items =
      Proposal
      |> Ash.Query.filter(id in ^Map.keys(changed))
      |> Ash.Query.load(@summary)
      |> Ash.read!()
      |> Enum.map(
        &%{
          proposal: &1,
          status: status(&1),
          changed_seq: Map.fetch!(changed, &1.id)
        }
      )
      |> Enum.sort_by(& &1.changed_seq)

    %{
      items: items,
      next_cursor: read |> List.last({Kernel.min(after_seq, head_seq), nil}) |> elem(0),
      head_seq: head_seq,
      has_more: rest != []
    }
  end

  defp records_after(resource, fleet_id, after_seq, head_seq) do
    fields = Enum.filter([:record_seq, :proposal_id], &Ash.Resource.Info.attribute(resource, &1))

    resource
    |> Ash.Query.filter(
      fleet_id == ^fleet_id and record_seq > ^after_seq and record_seq <= ^head_seq
    )
    |> Ash.Query.sort(record_seq: :asc)
    |> Ash.Query.limit(@changes_page + 1)
    |> Ash.Query.select(fields)
    |> Ash.read!()
    |> Enum.map(&{&1.record_seq, proposal_of(&1)})
  end

  defp proposal_of(%Proposal{id: id}), do: id
  defp proposal_of(%{proposal_id: id}), do: id
  defp proposal_of(_money_or_edits_record), do: nil

  @doc "The fleet's highest proposal number recorded so far, or 0."
  def highest_number!(fleet_id) do
    case latest_proposal!(fleet_id) do
      nil -> 0
      latest -> latest.number
    end
  end

  @doc """
  Every proposal, vote, cancellation and execution recorded from blocks
  `from..to` of the fleet, and from the `transactions` named wherever they
  were recorded, so a reading of those blocks can be checked against the
  record.
  """
  def recorded_in_blocks!(fleet_id, from, to, transactions \\ []) do
    Enum.flat_map(
      [
        &proposals_recorded_in_blocks!/5,
        &votes_recorded_in_blocks!/5,
        &cancellations_recorded_in_blocks!/5,
        &executions_recorded_in_blocks!/5
      ],
      & &1.(fleet_id, from, to, %{transactions: transactions}, actor: %System{})
    )
  end
end
