defmodule RegentsWeb.Keyfleet.ProposalsPage do
  @moduledoc """
  What a fleet's proposal pages show, read from the proposals and votes the
  chain reader recorded.

  `list/2` is the fleet's proposals, newest first, twenty to a page.
  `treasury_page/1` is the fleet's Treasury page: how many of its Keys have a
  vote now, its shared money once it is on chain (the latest reading of its
  treasury, its daily split, the advances still out and its latest money in
  and out), the votes carried out lately, its sales so far and what it has
  used of the site this month (`Regents.Keyfleet.Usage`).
  `detail/3` is one proposal with its votes, fifty to a page, each Key's
  latest vote and the Keys counted that have not voted, its calls in
  plain words and exactly as carrying it out sends them, and where it stands as the vote contract says at the latest
  block: its status, the keys counted and each tally, never worked out here.
  Once the fleet is on chain, each carries the network its wallet buttons
  send on; the buttons' steps are built by `Regents.Keyfleet.WalletSteps`. A page
  name that is not a proposal number is a page that doesn't exist.

  None of them depends on who is reading, so `first_pages/2` reads the ones
  most visitors open, the first page of the list, the Treasury page and the
  first page of each proposal on that list, once for every open page
  (`RegentsWeb.Keyfleet.FleetProposals`). The pages further back are read for the
  visit that asks for them.
  """

  alias Regents.Keyfleet.Chain
  alias Regents.Keyfleet.Fleets
  alias Regents.Keyfleet.Fleets.Rules
  alias Regents.Keyfleet.Proposals
  alias Regents.Keyfleet.Proposals.Actions
  alias Regents.Keyfleet.Treasury
  alias Regents.Keyfleet.WalletSteps.{Reads, VoteSteps}
  alias RegentsWeb.Keyfleet.WorkspacePage
  alias RegentsWeb.NotFoundError

  @number ~r/\A[1-9][0-9]{0,17}\z/
  @votes_page 50

  @doc """
  The page of proposals below the one `params` names, if it names one, with
  what the forms for new proposals start from.
  """
  def list(fleet_id, params) do
    before = number!(params["before"])

    with_fleet(fleet_id, fn fleet, reading ->
      listed(
        fleet,
        reading,
        Treasury.assets(fleet),
        before,
        Proposals.list_page(fleet_id, before)
      )
    end)
  end

  defp listed(fleet, reading, assets, before, {proposals, older?}) do
    Map.merge(reading, %{
      proposals: Enum.map(proposals, &summary(&1, fleet, assets)),
      first_page?: is_nil(before),
      older: if(older?, do: list_path(fleet.id, before: List.last(proposals).number)),
      propose: reading.deployed? && propose(fleet)
    })
  end

  # How many of the latest votes carried out the Treasury page lists.
  @carried 5
  # The most USDC the REGENT buyer turns in one piece (its `PIECE_USDC`).
  @piece_usdc 250_000_000
  # What the Treasury page shows of a month's usage (`Regents.Keyfleet.Usage.Month`).
  @usage [
    :month,
    :workspace_bytes,
    :workspace_items,
    :chat_posts,
    :chat_bytes,
    :notebook_seconds,
    :counted_at
  ]

  @doc """
  The fleet's Treasury page: indexed balances, money history and contract details.
  """
  def treasury_page(fleet_id) do
    with_fleet(fleet_id, fn fleet, reading ->
      treasury_shown(fleet, reading, Treasury.assets(fleet), Treasury.get_reading!(fleet_id))
    end)
  end

  defp treasury_shown(fleet, reading, assets, treasury_reading) do
    Map.merge(reading, %{
      treasury: reading.deployed? && treasury(fleet, treasury_reading, assets),
      carried:
        fleet.id
        |> Proposals.latest_carried_out(@carried)
        |> Enum.map(&summary(&1, fleet, assets)),
      progress: reading.deployed? && Chain.progress(fleet.id),
      manager_address: fleet.manager_address,
      usage: usage(fleet.id)
    })
  end

  # The fleet's usage this month as last counted, its figures alone, or nil
  # before its first count.
  defp usage(fleet_id) do
    with %{} = month <- Regents.Keyfleet.Usage.this_month(fleet_id),
         do: Map.take(month, @usage)
  end

  @doc "The path of the fleet's Treasury page."
  def treasury_path(fleet_id), do: "#{Regents.Keyfleet.Fleets.path(fleet_id)}/treasury"

  @doc """
  Proposal `number` and a page of its votes, from the one `params` names.
  """
  def detail(fleet_id, number, params) do
    votes_after = seq!(params["votes_after"])

    with_fleet(fleet_id, fn fleet, reading ->
      case Proposals.get_by_number(fleet_id, String.to_integer(number)) do
        nil ->
          Map.merge(reading, %{number: number, proposal: nil})

        proposal ->
          assets = Treasury.assets(fleet)
          balances = balances(Treasury.get_reading!(fleet_id))
          reads = if reading.deployed?, do: Reads.at_head()

          proposal
          |> shown(fleet, reading, assets, balances)
          |> Map.merge(votes(proposal, votes_after))
          |> Map.put(:on_chain, reading.deployed? && on_chain(reads, fleet, proposal.number))
      end
    end)
  end

  # A proposal no vote can change any more, as its records and the vote
  # contract both say: its votes are all in and its standing is settled.
  @settled [:rejected, :cancelled, :executed, :execution_expired]

  @doc """
  The pages of `fleet_id` most visitors open, read together for
  `RegentsWeb.Keyfleet.FleetProposals`: `list`, the first page of its proposals;
  `treasury`, its Treasury page; and `details`, the first page of each
  proposal on that list, by number, each as `detail/3` reads it.

  `held` answers the proposal's page from the last reading, or nil. A
  proposal that was already settled then, on its records and on chain, with
  every vote the contract counted in its records, keeps the votes, each Key's
  vote and the standing read then, since none can change; the rest
  of its page, its tally and what its calls come to at today's balance, is
  read again. Every other proposal on the list has its votes read again and
  its standing read at the latest block, at one block for all of them.
  """
  def first_pages(fleet_id, held) do
    case Fleets.get_fleet!(fleet_id) do
      nil ->
        missing = %{fleet_id: fleet_id, fleet_name: nil}
        %{list: missing, treasury: missing, details: %{}}

      fleet ->
        first_pages(fleet, about(fleet), held)
    end
  end

  defp first_pages(fleet, reading, held) do
    {proposals, _older?} = listing = Proposals.list_page(fleet.id, nil)
    assets = Treasury.assets(fleet)
    treasury_reading = Treasury.get_reading!(fleet.id)
    balances = balances(treasury_reading)

    pages =
      for proposal <- proposals,
          do: {shown(proposal, fleet, reading, assets, balances), held.(proposal.number)}

    reads =
      if reading.deployed? and Enum.any?(pages, fn {page, held} -> not settled?(page, held) end),
        do: Reads.at_head()

    %{
      list: listed(fleet, reading, assets, nil, listing),
      treasury: treasury_shown(fleet, reading, assets, treasury_reading),
      details:
        Map.new(Enum.zip(proposals, pages), fn {proposal, {page, held}} ->
          {proposal.number, first_detail(proposal, page, held, fleet, reads)}
        end)
    }
  end

  defp first_detail(proposal, page, held, fleet, reads) do
    if settled?(page, held) do
      Map.merge(
        page,
        Map.take(held, [:on_chain, :votes, :ballots, :agents, :more_votes, :first_votes])
      )
    else
      page
      |> Map.merge(votes(proposal, 0))
      |> Map.put(:on_chain, page.deployed? && on_chain(reads, fleet, proposal.number))
    end
  end

  defp settled?(%{proposal: %{status: status}}, %{
         proposal: %{status: held},
         on_chain: %{status: on_chain} = tally,
         ballots: ballots
       }),
       do:
         status in @settled and held in @settled and on_chain in @settled and
           recorded?(ballots, tally)

  defp settled?(_page, _held), do: false

  # Every vote the contract counted is in the records: a vote cast just before
  # voting closed can reach them after a reading that found it settled.
  defp recorded?(ballots, tally) do
    length(ballots.yes) == tally.yes and length(ballots.no) == tally.no and
      length(ballots.abstain) == tally.abstain and
      length(ballots.silent) == tally.counted - tally.yes - tally.no - tally.abstain
  end

  # A proposal's page but for its votes and where it stands on chain.
  defp shown(proposal, fleet, reading, assets, balances) do
    Map.merge(reading, %{
      number: Integer.to_string(proposal.number),
      proposal:
        Map.merge(summary(proposal, fleet, assets), details(proposal, fleet, assets, balances))
    })
  end

  defp votes(proposal, votes_after) do
    {votes, more?} = Proposals.votes_after(proposal.id, votes_after, @votes_page)
    path = &detail_path(proposal.fleet_id, proposal.number, &1)

    %{
      votes: Enum.map(votes, &vote/1),
      ballots: Proposals.key_ballots(proposal),
      agents: WorkspacePage.agent_names([proposal.proposer | Enum.map(votes, & &1.voter)]),
      more_votes: if(more?, do: path.(votes_after: List.last(votes).record_seq)),
      first_votes: if(votes_after > 0, do: path.([]))
    }
  end

  @doc "The path of the fleet's proposals, from `position`."
  def list_path(fleet_id, position \\ []),
    do: with_query("#{Regents.Keyfleet.Fleets.path(fleet_id)}/proposals", position)

  @doc "The path of one proposal's page, from `position` in its votes."
  def detail_path(fleet_id, number, position \\ []),
    do: with_query("#{Regents.Keyfleet.Fleets.path(fleet_id)}/proposals/#{number}", position)

  defp with_query(path, []), do: path
  defp with_query(path, query), do: path <> "?" <> URI.encode_query(query)

  @doc """
  An amount of an asset as every page shows it, `%{text: text, token: address
  | nil, symbol?: boolean}`, grouped: in its own units with its symbol when
  the token has reported both, cut to four decimal places (below one token,
  to its first four significant digits; the fleet's REGENT to two, as
  `regent/2` cuts it), and otherwise as the whole number the chain holds.
  `symbol?` says whether `text` ends in the symbol the token chose.
  Every asset but the ones the fleet's deployment names (ETH, its USDC and
  REGENT), known by their addresses, comes with its address as `token`, so a
  token calling itself USDC is never taken for it. `assets` is as `Regents.Keyfleet.Treasury.assets/1`
  reads them.
  """
  def amount(atoms, asset, %{known: known, details: details}) do
    {text, symbol?} =
      case {details[asset], asset in known} do
        {{"REGENT", decimals}, true} ->
          {"#{regent(atoms, decimals)} REGENT", true}

        {{symbol, decimals}, _known?} when is_binary(symbol) and is_integer(decimals) ->
          {"#{figure(atoms, decimals)} #{symbol}", true}

        _unknown ->
          {"#{units(atoms, 0)} in the smallest units of token", false}
      end

    %{text: text, token: if(asset not in known, do: asset), symbol?: symbol?}
  end

  defp with_fleet(fleet_id, read) do
    case Fleets.get_fleet!(fleet_id) do
      nil -> %{fleet_id: fleet_id, fleet_name: nil}
      fleet -> read.(fleet, about(fleet))
    end
  end

  # What every page of the fleet starts with.
  defp about(fleet) do
    deployed? = fleet.manager_address != nil

    %{
      fleet_id: fleet.id,
      fleet_name: fleet.name,
      deployed?: deployed?,
      chain_id: fleet.chain_id,
      catching_up?: deployed? and not Chain.fresh?(fleet.id)
    }
  end

  # The tokens a payment or an advance can be made in: ETH, REGENT, USDC and
  # any other token the treasury splits, by name.
  defp propose(fleet),
    do: %{
      assets:
        Enum.map(
          Treasury.payable_assets(fleet),
          &%{address: &1.address, name: pay_name(&1)}
        )
    }

  # A token as the payment form names it: those the fleet's deployment names
  # by name, any other with its address beside its symbol, so a token
  # calling itself USDC is never taken for it.
  defp pay_name(%{known?: true, symbol: symbol}), do: symbol

  defp pay_name(%{address: address, symbol: symbol}) when is_binary(symbol),
    do: "#{symbol} #{RegentFormat.short_address(address)}"

  defp pay_name(%{address: address}), do: "Token #{RegentFormat.short_address(address)}"

  defp summary(proposal, fleet, assets) do
    %{
      number: proposal.number,
      kind: kind(proposal.calls, fleet),
      actions: Enum.map(proposal.calls, &(&1 |> Actions.decode(fleet) |> said(assets, %{}))),
      status: Proposals.status(proposal),
      yes: proposal.yes_keys,
      no: proposal.no_keys,
      abstain: proposal.abstain_keys,
      counted: proposal.opening_count + proposal.late_keys,
      closes_at: proposal.closes_at,
      carry_out_from: Proposals.carry_out_from(proposal),
      text: words(proposal.words)
    }
  end

  # What kind of proposal it is, in a word or two, from what its calls do:
  # the kinds the form makes, and the calls only an agent could have sent.
  defp kind([], _fleet), do: "Decision"

  defp kind(calls, fleet) do
    case calls |> Enum.map(&(&1 |> Actions.decode(fleet) |> kind_of())) |> Enum.uniq() do
      [kind] -> kind
      _several -> "Several actions"
    end
  end

  defp kind_of({:pay, _asset, _to, _share}), do: "Payment"
  defp kind_of({:advance, _id, _operator, _asset, _share, _purpose}), do: "Advance"
  defp kind_of({:rate, _bps}), do: "Slice rate"
  defp kind_of({:signature, _change, _issued_at}), do: "Signature"
  defp kind_of({:edits, _token_id, _restricted?}), do: "Key edits"
  defp kind_of({:launch, _launch}), do: "Token launch"
  defp kind_of(:voted_split), do: "Slice release"
  defp kind_of({:admit_ousd, _token}), do: "New slice token"
  defp kind_of({:other, _target, _data}), do: "Unknown call"

  # A proposal's words, shown only as saved under its own fingerprint.
  defp words(nil), do: nil
  defp words(%{text: text}), do: text

  defp details(proposal, fleet, assets, balances) do
    %{
      proposer: proposal.proposer,
      author_key: proposal.author_key,
      content_hash: proposal.content_hash,
      opened_at: proposal.opened_at,
      execution_expiry: proposal.execution_expiry,
      carry_out_from: Proposals.waits?(proposal) && Proposals.carry_out_from(proposal),
      calls: Enum.map(proposal.calls, &call(&1, fleet, assets, balances)),
      executor: proposal.execution && proposal.execution.executor,
      cancelled_by: proposal.cancellation && proposal.cancellation.cancelled_by
    }
  end

  # Where the proposal stands as the vote contract says now, read at the
  # latest block, or `:unreadable` when the network can't be reached.
  defp on_chain(reads, fleet, number) do
    with {:ok, reads} <- reads,
         {:ok, standing} <- VoteSteps.proposal(reads, fleet, number),
         {:ok, status} <- VoteSteps.chain_status(reads, fleet, number) do
      Map.merge(standing, %{status: status, counted: standing.e0 + standing.late})
    else
      _unread -> :unreadable
    end
  end

  # The treasury's balance of each asset at its latest reading, if it has one.
  defp balances(nil), do: %{}
  defp balances(reading), do: Map.new(reading.assets, &{&1.asset, &1.held})

  # One call carrying the proposal out makes. In plain words: `text`, then
  # the wallet it names in full, if any, and for a payment or an
  # advance what its share comes to at the treasury's latest balance. Then
  # exactly what the vote contract sends: the contract, by name and address,
  # the function, if it is one this site knows, and the call's data, so a
  # voter can check the words against the call.
  defp call(recorded, fleet, assets, balances) do
    recorded
    |> Actions.decode(fleet)
    |> said(assets, balances)
    |> Map.merge(%{
      contract: contract_name(Actions.contract(recorded.target, fleet)),
      target: recorded.target,
      function: Actions.function(recorded.data),
      data: recorded.data
    })
  end

  defp said({:pay, asset, to, share}, assets, balances),
    do: %{
      text: "Pay #{share_of(share, asset, assets)} to",
      address: to,
      today: today(asset, share, assets, balances)
    }

  defp said({:advance, id, operator, asset, share, _purpose}, assets, balances),
    do: %{
      text: "Advance #{share_of(share, asset, assets)} (advance #{id}) to",
      address: operator,
      today: today(asset, share, assets, balances)
    }

  defp said({:rate, bps}, _assets, _balances),
    do: plain("Set the Daily Treasury Slice to Keys to #{units(bps, 2)}%")

  defp said({:signature, :approve, issued_at}, _assets, _balances),
    do: plain("Sign the fleet’s Lit wallet request #{request_time(issued_at)}")

  defp said({:signature, :revoke, issued_at}, _assets, _balances),
    do:
      plain("Withdraw the fleet’s signature on its Lit wallet request #{request_time(issued_at)}")

  defp said({:edits, token_id, true}, _assets, _balances),
    do: plain("Stop Key #{Rules.grouped(token_id)} changing the workspace")

  defp said({:edits, token_id, false}, _assets, _balances),
    do: plain("Let Key #{Rules.grouped(token_id)} change the workspace again")

  defp said({:launch, launch}, _assets, _balances),
    do: plain("Launch #{launch.name} (#{launch.symbol}) through Autolaunch, for the treasury")

  defp said(:voted_split, _assets, _balances),
    do: plain("Release the Daily Treasury Slice to Keys now")

  defp said({:admit_ousd, token}, _assets, _balances),
    do: plain("Add OUSD to the Daily Treasury Slice to Keys:", token)

  defp said({:other, _target, _data}, _assets, _balances),
    do: plain("A call Keyfleet doesn’t recognize. Check it before you vote.")

  defp plain(text, address \\ nil), do: %{text: text, address: address, today: nil}

  # The time a Lit request names, as its number of seconds and, when it is a
  # date at all, that date.
  defp request_time(issued_at) do
    case DateTime.from_unix(issued_at) do
      {:ok, at} -> "timed #{issued_at} (#{Calendar.strftime(at, "%-d %B %Y at %H:%M:%S UTC")})"
      {:error, _not_a_date} -> "timed #{issued_at}"
    end
  end

  # What a share of the treasury's balance of `asset` comes to now, or nil
  # before the treasury has been read.
  defp today(asset, share, assets, balances) do
    case balances do
      %{^asset => held} -> amount(div(held * share, 1_000_000), asset, assets)
      _unread -> nil
    end
  end

  defp contract_name(:treasury), do: "Fleet treasury"
  defp contract_name(:votes), do: "Fleet votes"
  defp contract_name(:manager), do: "Fleet manager"
  defp contract_name(:autolaunch), do: "Autolaunch"
  defp contract_name(:other), do: "Not a Keyfleet contract"

  # A share of the treasury's balance of a token, in parts per million, as
  # the treasury pays it out when the proposal is carried out.
  defp share_of(share, asset, %{details: details}) do
    name =
      case details[asset] do
        {symbol, _decimals} when is_binary(symbol) -> symbol
        _unknown -> "token #{RegentFormat.short_address(asset)}"
      end

    "#{units(share, 4)}% of the treasury’s #{name}"
  end

  defp vote(vote) do
    %{
      id: vote.id,
      voter: vote.voter,
      choice: vote.choice,
      keys: vote.token_ids
    }
  end

  defp treasury(fleet, reading, assets) do
    %{shown: shown, earlier?: earlier?} = Treasury.latest(fleet.id)

    %{
      address: fleet.treasury_address,
      history: Enum.map(shown, &event(&1, fleet, assets)),
      earlier?: earlier?,
      advances: Enum.map(Treasury.open_advances(fleet.id), &advance(&1, assets)),
      convert_typed: convert_typed(reading)
    }
    |> Map.merge(figures(fleet, reading, assets))
  end

  # What a press of Buy REGENT starts with: what is waiting, at most
  # one piece of 250 USDC, as typed. Typed in by hand until a reading says.
  defp convert_typed(nil), do: ""

  defp convert_typed(reading) do
    case Decimal.to_integer(reading.conversion_waiting) do
      0 -> ""
      waiting -> waiting |> min(@piece_usdc) |> units(6) |> String.replace(",", "")
    end
  end

  defp figures(_fleet, nil, _assets), do: %{read?: false}

  defp figures(fleet, reading, assets) do
    %{
      read?: true,
      as_of: reading.block_time,
      waiting: amount(Decimal.to_integer(reading.conversion_waiting), fleet.usdc_address, assets),
      balances:
        Enum.map(
          reading.assets,
          &%{
            asset: &1.asset,
            held_atomic: Integer.to_string(&1.held),
            backed_atomic: Integer.to_string(&1.backed),
            held: amount(&1.held, &1.asset, assets),
            backed: amount(&1.backed, &1.asset, assets)
          }
        ),
      split_rate: "#{units(reading.daily_split_bps, 2)}%",
      next_run_at: reading.next_run_at,
      waiting_since:
        Treasury.waiting_since(reading, assets.details, Treasury.last_piece_turned_at(fleet.id))
    }
  end

  # One line of the money history: what happened, how much, for money paid
  # or advanced to whom, and for REGENT bought the USDC it cost.
  defp event(%{kind: :split_allocated} = event, _fleet, assets) do
    shared = Decimal.to_integer(event.per_key) * Decimal.to_integer(event.keys)

    %{
      id: event.id,
      kind: event.kind,
      amount: amount(shared, event.asset, assets),
      account: nil,
      spent: nil
    }
  end

  defp event(%{kind: :protocol_share_sent} = event, fleet, assets),
    do: %{
      id: event.id,
      kind: event.kind,
      amount: amount(Decimal.to_integer(event.amount), fleet.usdc_address, assets),
      account: nil,
      spent: nil
    }

  defp event(%{kind: :regent_bought} = event, fleet, assets),
    do: %{
      id: event.id,
      kind: event.kind,
      amount: amount(Decimal.to_integer(event.regent_out), fleet.regent_address, assets),
      account: nil,
      spent: amount(Decimal.to_integer(event.usdc_in), fleet.usdc_address, assets)
    }

  defp event(event, _fleet, assets),
    do: %{
      id: event.id,
      kind: event.kind,
      amount: amount(Decimal.to_integer(event.amount), event.asset, assets),
      account: if(event.kind in [:paid, :advanced], do: event.account),
      spent: nil
    }

  # An advance still out, with what is left in whole tokens as a return of
  # all of it is typed.
  defp advance(advance, assets) do
    outstanding = Decimal.to_integer(advance.outstanding)
    decimals = assets.details |> Map.get(advance.asset, {nil, nil}) |> elem(1)

    %{
      id: Decimal.to_integer(advance.advance_id),
      operator: advance.operator,
      amount: amount(Decimal.to_integer(advance.amount), advance.asset, assets),
      outstanding: amount(outstanding, advance.asset, assets),
      typed: units(outstanding, decimals || 0) |> String.replace(",", "")
    }
  end

  defp number!(nil), do: nil

  defp number!(value) when is_binary(value) do
    if Regex.match?(@number, value), do: String.to_integer(value), else: raise(NotFoundError)
  end

  defp number!(_value), do: raise(NotFoundError)

  defp seq!(nil), do: 0
  defp seq!(value), do: number!(value)

  @doc """
  `atoms` of a token with `decimals` places as every page shows them: whole
  tokens, thousands grouped, cut to four decimal places, or below one token
  to its first four significant digits. Cut, never rounded up, so a page
  never shows more than there is.
  """
  def figure(atoms, decimals) do
    digits = atoms |> Integer.to_string() |> String.length()

    if atoms > 0 and digits <= decimals,
      do: cut(atoms, decimals, min(decimals, decimals - digits + 4)),
      else: cut(atoms, decimals, min(decimals, 4))
  end

  @doc """
  `atoms` of the fleet's REGENT, which has `decimals` places, as every page
  shows them: whole tokens, thousands grouped, cut to two decimal places, or
  "<0.01" when there is some but less than that. Cut, never rounded up.
  """
  def regent(atoms, decimals) do
    case cut(atoms, decimals, 2) do
      "0" when atoms > 0 -> "<0.01"
      shown -> shown
    end
  end

  defp cut(atoms, decimals, kept) do
    step = Integer.pow(10, decimals - kept)
    units(atoms - rem(atoms, step), decimals)
  end

  @doc """
  `atoms` of a token with `decimals` places, in whole tokens, thousands
  grouped. Whole numbers throughout: an amount can be any uint256, more
  digits than decimal arithmetic keeps.
  """
  def units(atoms, decimals) do
    scale = Integer.pow(10, decimals)

    fraction =
      atoms
      |> rem(scale)
      |> Integer.to_string()
      |> String.pad_leading(decimals, "0")
      |> String.trim_trailing("0")

    case fraction do
      "" -> Rules.grouped(div(atoms, scale))
      fraction -> "#{Rules.grouped(div(atoms, scale))}.#{fraction}"
    end
  end
end
