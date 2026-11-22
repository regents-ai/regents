defmodule Regents.Keyfleet.Agents.Upkeep do
  @moduledoc """
  What an agent's scheduled run needs from one fleet, worked out from the chain
  reader's records and never from anything the agent says about itself: when
  each Key it can mark stops being present, the proposals its person's Keys or
  its own haven't decided, the fleet's money that has waited too long for
  anyone to move it, and how many marks its wallet's ETH would pay for.

  `setup/4` reads the same figures as the five states an agent's setup ends in,
  and `person_agents/2` the same states for the agents a signed-in person has
  paired, with `pays?/2` the chain's answer on gas. Both name the same steps:
  an agent with a Key or a shard of its own to mark finishes when all five are
  done, and one with neither when it is paired and its scheduled check-ins
  repeat, a shard being only a tip for it. `unscheduled/2` names a person's
  agents with no scheduled check-in seen, by the same `schedule` state.
  """

  alias Regents.Account.Actors.Human
  alias Regents.Keyfleet.Agents
  alias Regents.Keyfleet.Agents.CheckInStatus
  alias Regents.Keyfleet.Fleets
  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.Proposals
  alias Regents.Keyfleet.Treasury
  alias Regents.Keyfleet.WalletSteps.Reads

  # `KeyfleetPresence.WINDOW`.
  @window_seconds 172_800
  # More than a day, so a daily run that comes a little early still marks and
  # the next one never arrives after the Key's 48 hours end.
  @due_within_seconds 30 * 3600
  # What marking costs at most for each Key, and the tip a wallet adds.
  @gas_per_key 60_000
  @tip_wei 1_000_000

  @doc """
  `%{presence: %{marking_due, keys}, proposals_awaiting: [...], money_waiting:
  [...], gas: gas}` for `actor` in the fleet. `money_waiting` is
  `Regents.Keyfleet.Treasury.late_steps/1`. `read_gas?` says whether to ask the chain
  for the wallet's ETH; `gas` is nil when it wasn't asked, when the agent has
  no Key to mark, or when the chain doesn't answer.
  """
  def read(actor, fleet_id, read_gas?) do
    now = DateTime.utc_now()
    keys = Keys.held_keys(actor, fleet_id)
    markable = for %{for_person: false, token_id: token_id} <- keys, do: token_id

    %{
      presence: presence(fleet_id, markable, now),
      proposals_awaiting: awaiting(fleet_id, Enum.map(keys, & &1.token_id), now),
      money_waiting: fleet_id |> Fleets.get_fleet!() |> Treasury.late_steps(),
      gas: if(read_gas? and markable != [], do: gas(actor.wallet_address, length(markable)))
    }
  end

  @doc """
  The five states of an agent's setup, read from `upkeep` (`read/3`, with its
  gas), the one thing to do next, nil once every step it has is done, and a
  tip, nil but for an agent with no Key or shard of its own to mark: that its
  person may give it a shard, which it doesn't need.
  """
  def setup(actor, fleet_id, profile, upkeep) do
    check_in = profile && Agents.get_check_in!(profile.id, fleet_id)
    keys = upkeep.presence.keys

    states =
      check_in
      |> states(keys, DateTime.utc_now())
      |> Map.merge(%{paired: match?(%Human{}, actor.pairing), gas: can_pay?(keys, upkeep.gas)})

    Map.merge(states, %{next_step: next_step(states, keys), tip: tip(keys)})
  end

  @doc """
  The agents `person` has paired, each as `%{wallet, name, key_count, steps,
  schedule, marked, repeated, run_missed, lapses_at}`, in the fleet. `steps`
  are the states its setup must reach, in order, as `setup/4` counts them.
  `lapses_at` is when the first of its Keys stops being present. Nothing here
  reads the chain, so a page draws them at once and asks `pays?/2` beside them.
  """
  def person_agents(%Human{} = person, fleet_id) do
    now = DateTime.utc_now()
    agents = Agents.my_agents(person)
    check_ins = Agents.check_ins_by_wallet(Enum.map(agents, & &1.wallet), fleet_id)

    for %{wallet: wallet, name: name} <- agents do
      check_in = Map.get(check_ins, wallet)
      keys = presence(fleet_id, wallet_keys(wallet, fleet_id), now).keys

      check_in
      |> states(keys, now)
      |> Map.merge(%{
        wallet: wallet,
        name: name,
        key_count: length(keys),
        steps: steps(keys),
        run_missed: match?({:paused, _label}, CheckInStatus.derive(check_in, now)),
        lapses_at: lapses_at(keys)
      })
    end
  end

  @doc """
  Each agent `person` has paired that has no scheduled check-in seen in each
  of `fleet_ids`, as `setup/4`'s `schedule` reads it, fleet by fleet:
  `%{fleet_id, wallet, name, status, light}`, with the words and the light
  `CheckInStatus` gives its check-ins there. An agent whose runs come, or
  that only waits between them, has had one seen and isn't here.
  """
  def unscheduled(%Human{} = person, fleet_ids) do
    now = DateTime.utc_now()
    agents = Agents.my_agents(person)
    wallets = Enum.map(agents, & &1.wallet)

    for fleet_id <- fleet_ids,
        check_ins = Agents.check_ins_by_wallet(wallets, fleet_id),
        %{wallet: wallet, name: name} <- agents,
        not scheduled?(check_ins[wallet]) do
      {_status, words} = CheckInStatus.derive(check_ins[wallet], now)
      light = CheckInStatus.light(check_ins[wallet], now)
      %{fleet_id: fleet_id, wallet: wallet, name: name, status: words, light: light}
    end
  end

  @doc """
  Whether `wallet` can pay to mark `key_count` Keys at the latest block: nil with
  none to mark or when the chain doesn't answer.
  """
  def pays?(_wallet, 0), do: nil
  def pays?(wallet, key_count), do: can_pay?([key_count], gas(wallet, key_count))

  # A scheduled check-in declares the schedule; one of the agent's in the
  # fleet has arrived.
  defp scheduled?(check_in), do: check_in != nil and check_in.schedule_minutes != nil

  defp states(check_in, keys, now) do
    %{
      schedule: scheduled?(check_in),
      marked: keys != [] and Enum.all?(keys, &needs_no_mark?(&1.present_until, now)),
      repeated: CheckInStatus.repeating?(check_in, now)
    }
  end

  defp wallet_keys(wallet, fleet_id) do
    held = Keys.keys_held_in_fleet!(fleet_id, [wallet])
    sharded = for %{fleet_id: ^fleet_id} = shard <- Keys.active_shards_held_by!(wallet), do: shard

    (held ++ sharded) |> Enum.map(& &1.token_id) |> Enum.uniq() |> Enum.sort()
  end

  defp lapses_at(keys) do
    keys
    |> Enum.map(& &1.present_until)
    |> Enum.reject(&is_nil/1)
    |> Enum.min(DateTime, fn -> nil end)
  end

  # With no Key to mark there is nothing to pay for yet, and nil too when the
  # chain didn't answer. A wallet with code may have its fee paid for it.
  defp can_pay?([], _gas), do: nil
  defp can_pay?(_keys, nil), do: nil
  defp can_pay?(_keys, %{pays_own_fee: false}), do: true
  defp can_pay?(_keys, %{marks_left: left}), do: left > 0

  # The states an agent's setup must reach, in order. Marking Keys present is
  # part of it only for an agent with a Key or a shard of its own to mark; one
  # with neither acts as its person's Key and needs no shard (`tip/1`).
  defp steps([]), do: [:paired, :schedule, :repeated]
  defp steps(_keys), do: [:paired, :gas, :schedule, :marked, :repeated]

  defp next_step(states, keys), do: Enum.find_value(steps(keys), &step(&1, states[&1]))

  defp tip([]),
    do:
      "Optional, for presence only: your person may give you a shard of their Key, so you " <>
        "can mark it present for them. Without one they mark it themselves, and nothing " <>
        "else needs it: the may field says what you can do now."

  defp tip(_keys), do: nil

  # Each step past pairing is about presence or scheduled check-ins, never
  # what the agent may read or write (`may`), and the schedule's two are what
  # Keyfleet has seen arrive, never what the agent has set up on its side.
  defp step(_step, true), do: nil
  defp step(:paired, false), do: "Ask your person for a pairing code."

  defp step(:gas, nil),
    do:
      "For presence only: the chain didn't answer whether your wallet can pay to mark your " <>
        "Keys. Read this again in a minute."

  defp step(:gas, false),
    do: "For presence only: ask your person to send your wallet ETH on Base to pay for marks."

  defp step(:schedule, false),
    do:
      "No scheduled check-in for this fleet has reached Keyfleet yet. Keyfleet sees one when " <>
        "a run your scheduler starts syncs this fleet with run.kind scheduled: schedule your " <>
        "check-ins, then start one now."

  defp step(:marked, false), do: "For presence only: mark your Keys present."

  # Not repeating is exactly one of these two (`CheckInStatus.repeating?/2`);
  # a new interval clears the confirmation (`Changes.ScheduledCheckIn`).
  defp step(:repeated, false),
    do:
      "Keyfleet hasn't confirmed your schedule for this fleet, or your last scheduled " <>
        "check-in is more than twice run.every_minutes plus 45 minutes old. Keep checking " <>
        "in with the same run.every_minutes, and read this again after your next check-in."

  # A Key needs no mark while its 48 hours run, and while it waits for its
  # automatic start, which comes by itself and before which the contract
  # refuses a mark (`maturesAt`): both end at `present_until`. Only the first
  # is present now, as the contract counts it (`KeyfleetPresence.isActive`,
  # the `present` calculation of `Regents.Keyfleet.Keys.KeyAttachment`). An agent's
  # `marked` state reads it.
  defp needs_no_mark?(nil, _now), do: false
  defp needs_no_mark?(present_until, now), do: DateTime.after?(present_until, now)

  defp presence(fleet_id, token_ids, now) do
    last = Keys.last_presence(fleet_id, token_ids)

    keys =
      Enum.map(token_ids, &%{token_id: &1, present_until: present_until(Map.get(last, &1))})

    %{marking_due: Enum.any?(keys, &due?(&1, now)), keys: keys}
  end

  defp present_until(%{kind: kind, at: at}) when kind in [:present, :scheduled],
    do: DateTime.add(at, @window_seconds)

  defp present_until(_cleared_or_none), do: nil

  defp due?(%{present_until: nil}, _now), do: true

  defp due?(%{present_until: until}, now),
    do: DateTime.diff(until, now) <= @due_within_seconds

  defp awaiting(_fleet_id, [], _now), do: []

  defp awaiting(fleet_id, token_ids, now) do
    for proposal <- Proposals.votable(fleet_id, now),
        undecided = token_ids -- Enum.flat_map(proposal.votes, & &1.token_ids),
        undecided != [] do
      counted = proposal.opening_count + proposal.late_keys

      %{
        number: proposal.number,
        status: Proposals.status(proposal, now),
        closes_at: proposal.closes_at,
        moves_money: Proposals.waits?(proposal),
        counted: counted,
        needed: Proposals.approvals_needed(counted),
        yes_votes: proposal.yes_keys,
        no_votes: proposal.no_keys,
        undecided: undecided,
        counted_at_opening: counted_at_opening(fleet_id, undecided, proposal)
      }
    end
  end

  # The Keys the contract counted when the proposal opened: each one's last
  # record before it is a renewal or an automatic start whose 48 hours were
  # running (`Regents.Keyfleet.Proposals.Calculations.LateKeys`).
  defp counted_at_opening(fleet_id, token_ids, proposal) do
    last = Keys.last_presence(fleet_id, token_ids, {proposal.block_number, proposal.log_index})

    Enum.filter(token_ids, fn token_id ->
      case Map.get(last, token_id) do
        %{kind: kind, at: at} when kind in [:present, :scheduled] ->
          DateTime.compare(at, proposal.opened_at) != :gt and
            DateTime.diff(proposal.opened_at, at) < @window_seconds

        _cleared_or_none ->
          false
      end
    end)
  end

  defp gas(wallet, key_count) do
    with {:ok, %Reads{head: head} = reads} <- Reads.at_head(),
         {:ok, wei} <- Reads.balance(reads, wallet),
         {:ok, pays_own_fee?} <- Reads.pays_own_fee?(reads, wallet) do
      cost = key_count * @gas_per_key * (2 * head.base_fee + @tip_wei)
      %{wei: Integer.to_string(wei), marks_left: div(wei, cost), pays_own_fee: pays_own_fee?}
    else
      {:error, _reason} -> nil
    end
  end
end
