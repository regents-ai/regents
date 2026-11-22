defmodule Regents.Keyfleet.WalletSteps.VoteSteps do
  @moduledoc """
  The steps of a fleet's vote: casting ballots, proposing, cancelling and
  carrying a proposal out. `Regents.Keyfleet.WalletSteps.Build` describes what every
  builder answers.

  A ballot is cast with every key the signer may vote at the head
  (`Regents.Keyfleet.WalletSteps.Build.own_keys/3`): those it holds, and
  those it holds an active shard of while the key's agent voting is on, less
  any sold under two days ago, which the vote contract refuses. While a
  proposal that moves money waits its day after closing, the one ballot the
  vote contract takes is No. A
  proposal is made with one key, and its calls come from the kind of proposal
  chosen (`Regents.Keyfleet.Proposals.Actions`). Pages name Keys by their number in
  the fleet; every step names them by their id in the Key collection.
  """

  alias RegentChain.{Call, Review}
  alias Regents.Keyfleet.Fleets.Fleet
  alias Regents.Keyfleet.Proposals
  alias Regents.Keyfleet.Proposals.Actions
  alias Regents.Keyfleet.Treasury
  alias Regents.Keyfleet.WalletSteps.{Build, Reads, Typed}

  # The contract's `Status`, in its order.
  @statuses [:open, :waiting, :approved, :rejected, :cancelled, :executed, :execution_expired]
  # The contract's `Choice`, in its order from 1.
  @choices [{"yes", 1}, {"no", 2}, {"abstain", 3}]
  @execute "execute(uint256,(address,uint256,bytes)[])"
  @propose "propose(uint256,bytes32,(address,uint256,bytes)[])"
  # A proposal's most bytes, as `Regents.Keyfleet.Proposals.Words` keeps them.
  @text_bytes 4_000
  # Each launch field's most bytes, as Autolaunch v2's factory takes them.
  @launch_fields [name: 64, symbol: 16, description: 512, website: 256, image: 256]
  # The kinds of proposal whose calls move money, which the vote contract
  # refuses during a fleet's first 7 days of sales.
  @money_kinds ["pay", "launch"]
  # How many lapsed presences the vote contract clears inside a proposal, and
  # in one press of the step that clears them first.
  @sweep_limit 256

  # The form fields each kind of proposal is built from, beside its kind, Key
  # and words.
  @kind_fields %{
    "decision" => [],
    "pay" => ["asset", "share", "recipient"],
    "rate" => ["rate"],
    "edits" => ["target", "restricted"],
    "launch" => for({name, _bytes} <- @launch_fields, do: "#{name}")
  }

  @doc "The most bytes each of a proposal's text fields takes, by its name in the form."
  def field_bytes, do: [text: @text_bytes] ++ @launch_fields

  @doc """
  The form fields a proposal of `kind` is built from: its kind, its Key, its
  words and its kind's own. Nothing else in the form is read for it, so a
  field of another kind never holds it back.
  """
  def fields(kind), do: ["kind", "key", "text" | Map.get(@kind_fields, kind, [])]

  @doc false
  def steps(:ballot, %{fleet: fleet, signer: signer, proposal: proposal}) do
    figures = %{keys: [], status: nil}

    with {:ok, reads} <- Reads.at_head(),
         {candidates, unread} = Build.own_keys(reads, fleet, signer),
         {:ok, status} <- status(reads, fleet, proposal),
         {:ok, standing} <- Reads.acting(reads, fleet, signer, candidates, "mayGovern"),
         governed = for(key <- candidates, match?({_holder, true}, standing[key]), do: key),
         {:ok, maturity} <- Reads.each(governed, &matures_at(reads, fleet, &1, figures)) do
      now = DateTime.to_unix(Reads.now(reads))
      keys = for {key, at} <- Enum.zip(governed, maturity), at != nil and at <= now, do: key

      steps =
        for {name, choice} <- @choices do
          Review.step(
            name,
            fleet.votes_address,
            Call.encode("castBallot(uint256,uint256[],uint8)", [
              proposal,
              Enum.map(keys, &Fleet.onchain_token_id(fleet, &1)),
              choice
            ])
          )
        end

      {:ok, steps,
       %{
         keys: keys,
         undecided: keys -- Proposals.voted_keys(fleet.id, proposal),
         status: status,
         blocked: ballot_blocked(status, governed, keys, unread)
       }, unread}
    else
      _unread -> {:problem, :unread, figures}
    end
  end

  # Whoever may vote the proposal's key may cancel it until it is carried
  # out: while it is open, waiting or approved.
  def steps(:cancel, %{fleet: fleet, signer: signer, proposal: proposal}) do
    figures = %{status: nil}

    with {:ok, reads} <- Reads.at_head(),
         {:ok, status} <- status(reads, fleet, proposal),
         {:ok, author} <- author_key(reads, fleet, proposal),
         {:ok, %{^author => {_holder, governs?}}} <-
           Reads.acting(reads, fleet, signer, [author], "mayGovern") do
      reason =
        cond do
          status not in [:open, :waiting, :approved] -> status
          not governs? -> :not_your_key
          true -> nil
        end

      {:ok,
       [Review.step("cancel", fleet.votes_address, Call.encode("cancel(uint256)", [proposal]))],
       %{status: status, blocked: if(reason, do: %{"cancel" => reason}, else: %{})}}
    else
      _unread -> {:problem, :unread, figures}
    end
  end

  # Anyone may carry out an approved proposal, with its exact calls as the
  # chain reader recorded them. A proposal that moves money waits a day after
  # its vote passes, and the vote contract refuses it until then.
  def steps(:carry_out, %{fleet: fleet, proposal: proposal}) do
    figures = %{status: nil}

    with %{calls: calls} = recorded <- Proposals.get_by_number(fleet.id, proposal),
         {:ok, reads} <- Reads.at_head(),
         {:ok, status} <- status(reads, fleet, proposal) do
      data = Call.encode(@execute, [proposal, Enum.map(calls, &{&1.target, &1.value, &1.data})])
      from = Proposals.carry_out_from(recorded)

      blocked =
        cond do
          status == :waiting -> %{"carry_out" => {:carry_out_from, from}}
          status != :approved -> %{"carry_out" => status}
          true -> %{}
        end

      {:ok, [Review.step("carry_out", fleet.votes_address, data)],
       %{status: status, blocked: blocked}}
    else
      nil -> {:problem, :not_recorded, figures}
      _unread -> {:problem, :unread, figures}
    end
  end

  # One proposal of the kind chosen, made with the Key typed. The vote
  # contract keeps it open to votes for `Regents.Keyfleet.Proposals.vote_hours/0`;
  # `closes_at` is when that ends if it is made at the latest block. Its text
  # is hashed into the proposal; the text itself stays off the chain. The vote
  # contract refuses a Key sold less than two days ago, and a proposal that
  # moves money during the fleet's first 7 days of sales, so those presses are
  # certain to fail. So is one made while more lapsed presences wait than the
  # contract clears inside a proposal: the steps then start with clearing
  # them, which anyone may do. `governs?` says whether the signer may vote the
  # Key at all, whatever else blocks the step. Only the kind's own fields are
  # read (`fields/1`).
  def steps(:propose, %{fleet: fleet, signer: signer, inputs: inputs}) do
    kind = Build.field(inputs, "kind")
    inputs = Map.take(inputs, fields(kind))

    with {:ok, key} <- Build.typed(inputs, "key", &Typed.key/1, %{kind: kind}),
         figures = %{kind: kind, key: key},
         {:ok, text} <- Build.typed(inputs, "text", &Typed.text(&1, :text, @text_bytes), figures),
         {:ok, reads} <- reads(figures),
         {:ok, action, details} <- action(kind, fleet, inputs, reads, text, figures),
         {:ok, %{^key => {_holder, governs?}}} <- acting(reads, fleet, signer, key, figures),
         {:ok, opens_at} <- read(reads, fleet.votes_address, "treasuryOpensAt()", figures),
         {:ok, matures_at} <- matures_at(reads, fleet, key, figures),
         {:ok, lapsed?} <- lapsed?(reads, fleet, figures) do
      now = DateTime.to_unix(Reads.now(reads))
      hours = Proposals.vote_hours()
      closes_at = now + hours * 3600
      content_hash = content_hash(text)
      calls = Actions.encode(action, fleet)
      reason = propose_blocked(kind, governs?, matures_at, opens_at, lapsed?, now)

      figures =
        Map.merge(figures, %{
          hours: hours,
          closes_at: DateTime.from_unix!(closes_at),
          content_hash: content_hash,
          action: details,
          governs?: governs?,
          blocked: if(reason, do: %{"propose" => reason}, else: %{})
        })

      propose =
        Review.step(
          "propose",
          fleet.votes_address,
          Call.encode(@propose, [Fleet.onchain_token_id(fleet, key), content_hash, calls])
        )

      {:ok, clear_first(lapsed?, fleet) ++ [propose], figures}
    end
  end

  defp propose_blocked(kind, governs?, matures_at, opens_at, lapsed?, now) do
    cond do
      not governs? -> :not_your_key
      matures_at == nil or matures_at > now -> :too_new
      kind in @money_kinds and (opens_at == 0 or opens_at > now) -> opening(opens_at)
      lapsed? -> :clear_first
      true -> nil
    end
  end

  defp clear_first(false, _fleet), do: []

  defp clear_first(true, fleet),
    do: [
      Review.step(
        "sweep",
        fleet.votes_address,
        Call.encode("sweepExpired(uint256)", [@sweep_limit])
      )
    ]

  # Whether more lapsed presences wait than a proposal clears itself, asked of
  # the vote contract by simulating a clear of that many.
  defp lapsed?(reads, fleet, figures) do
    case Reads.many(reads, fleet.votes_address, "sweepExpired(uint256)", [@sweep_limit], [
           {:uint, 256},
           :bool
         ]) do
      {:ok, [_moved, due?]} -> {:ok, due?}
      {:error, _reason} -> {:problem, :unread, figures}
    end
  end

  # Why each choice of a ballot is certain to fail, if it is. `governed` is
  # the keys the signer may vote and `keys` those of them old enough to.
  defp ballot_blocked(status, _governed, _keys, _unread) when status not in [:open, :waiting],
    do: every_choice(:voting_closed)

  # Only a list of the signer's Keys brought up to the head says it has none
  # to vote; one the chain didn't bring up holds no ballot back.
  defp ballot_blocked(_status, [], _keys, nil), do: every_choice(:no_keys)
  defp ballot_blocked(_status, _governed, [], nil), do: every_choice(:too_new)

  # A money proposal waiting its day takes only No ballots, which cancel it
  # once Yes no longer reaches the bar.
  defp ballot_blocked(:waiting, _governed, _keys, _unread),
    do: Map.delete(every_choice(:only_no), "no")

  defp ballot_blocked(:open, _governed, _keys, _unread), do: %{}

  defp every_choice(reason), do: Map.new(@choices, fn {name, _choice} -> {name, reason} end)

  @doc "The hash a proposal's text is kept on the chain as."
  def content_hash(text),
    do: "0x" <> Base.encode16(ExKeccak.hash_256(text), case: :lower)

  defp action("decision", _fleet, _inputs, _reads, _text, _figures),
    do: {:ok, :decision, :decision}

  defp action("pay", fleet, inputs, reads, _text, figures) do
    with {:ok, asset, share, amount, to} <- payment(fleet, inputs, reads, figures) do
      {:ok, {:pay, asset.address, to, share}, {:pay, asset, to, share, amount}}
    end
  end

  defp action("rate", _fleet, inputs, _reads, _text, figures) do
    with {:ok, bps} <- Build.typed(inputs, "rate", &Typed.rate/1, figures),
         do: {:ok, {:rate, bps}, {:rate, bps}}
  end

  defp action("edits", _fleet, inputs, _reads, _text, figures) do
    with {:ok, target} <- Build.typed(inputs, "target", &Typed.target/1, figures),
         {:ok, restricted?} <- Build.typed(inputs, "restricted", &Typed.restricted/1, figures),
         do: {:ok, {:edits, target, restricted?}, {:edits, target, restricted?}}
  end

  defp action("launch", _fleet, inputs, _reads, _text, figures) do
    with {:ok, fields} <- Reads.each(@launch_fields, &launch_field(inputs, &1, figures)) do
      launch = Map.new(fields)
      {:ok, {:launch, launch}, {:launch, launch}}
    end
  end

  defp action(_kind, _fleet, _inputs, _reads, _text, figures),
    do: {:problem, :kind_unknown, figures}

  defp launch_field(inputs, {name, bytes}, figures) do
    with {:ok, value} <- Build.typed(inputs, "#{name}", &Typed.text(&1, name, bytes), figures),
         do: {:ok, {name, value}}
  end

  # The token, share and wallet of a payment: a token the
  # treasury holds, by address, and a share of the treasury's balance of it,
  # in parts per million. The treasury pays that share of its balance when the
  # proposal is carried out; `amount` is what it comes to at the latest block.
  defp payment(fleet, inputs, reads, figures) do
    with {:ok, asset} <- asset(fleet, inputs, figures),
         figures = Map.put(figures, :asset, asset),
         {:ok, share} <- Build.typed(inputs, "share", &Typed.share/1, figures),
         {:ok, to} <-
           Build.typed(inputs, "recipient", &Typed.address(&1, :recipient_unreadable), figures),
         {:ok, held} <- held(reads, fleet, asset, figures) do
      {:ok, asset, share, div(held * share, 1_000_000), to}
    end
  end

  defp held(reads, fleet, %{address: address}, figures) do
    read =
      if address == Treasury.native(),
        do: Reads.balance(reads, fleet.treasury_address),
        else:
          Reads.one(reads, address, "balanceOf(address)", [fleet.treasury_address], {:uint, 256})

    case read do
      {:ok, held} -> {:ok, held}
      {:error, _reason} -> {:problem, :unread, figures}
    end
  end

  defp asset(fleet, inputs, figures) do
    case Enum.find(Treasury.payable_assets(fleet), &(&1.address == Build.field(inputs, "asset"))) do
      nil -> {:problem, :asset_unreadable, figures}
      asset -> {:ok, asset}
    end
  end

  defp reads(figures) do
    case Reads.at_head() do
      {:ok, reads} -> {:ok, reads}
      {:error, _reason} -> {:problem, :unread, figures}
    end
  end

  defp read(reads, to, signature, figures) do
    case Reads.one(reads, to, signature, [], {:uint, 256}) do
      {:ok, value} -> {:ok, value}
      {:error, _reason} -> {:problem, :unread, figures}
    end
  end

  # A Key's first second of taking part; a Key not sold yet never may.
  defp matures_at(reads, fleet, key, figures) do
    onchain = Fleet.onchain_token_id(fleet, key)

    case Reads.one(reads, fleet.votes_address, "maturesAt(uint256)", [onchain], {:uint, 64}) do
      {:ok, at} -> {:ok, at}
      {:error, :reverted} -> {:ok, nil}
      {:error, _reason} -> {:problem, :unread, figures}
    end
  end

  defp opening(0), do: :sales_not_open
  defp opening(opens_at), do: {:opens_at, DateTime.from_unix!(opens_at)}

  defp acting(reads, fleet, signer, key, figures) do
    case Reads.acting(reads, fleet, signer, [key], "mayGovern") do
      {:ok, standing} -> {:ok, standing}
      {:error, _reason} -> {:problem, :unread, figures}
    end
  end

  defp status(reads, fleet, proposal) do
    with {:ok, index} <-
           Reads.one(reads, fleet.votes_address, "status(uint256)", [proposal], {:uint, 8}),
         status when status != nil <- Enum.at(@statuses, index) do
      {:ok, status}
    else
      nil -> {:error, :unknown_status}
      failure -> failure
    end
  end

  @doc """
  A proposal as the vote contract holds it now: its key counts at opening and
  since, its tallies, and the key it was made with.
  """
  def proposal(reads, fleet, proposal) do
    with {:ok, words} <-
           Reads.many(
             reads,
             fleet.votes_address,
             "proposal(uint256)",
             [proposal],
             proposal_types()
           ) do
      [_content, _actions, _hash, author, _revision, _opened, _closes, _expiry | counts] = words
      [e0, late, yes, no, abstain, _cancelled, _executed] = counts

      with {:ok, author_key} <- Fleet.key_number(fleet, author),
           do:
             {:ok,
              %{author_key: author_key, e0: e0, late: late, yes: yes, no: no, abstain: abstain}}
    end
  end

  defp proposal_types,
    do:
      [:bytes32, :bytes32, :bytes32, {:uint, 64}, {:uint, 48}] ++
        List.duplicate({:uint, 64}, 3) ++ List.duplicate({:uint, 32}, 5) ++ [:bool, :bool]

  defp author_key(reads, fleet, proposal) do
    with {:ok, %{author_key: author}} <- proposal(reads, fleet, proposal), do: {:ok, author}
  end

  @doc "Where a proposal stands as the vote contract says now, read at the head."
  def chain_status(reads, fleet, proposal), do: status(reads, fleet, proposal)
end
