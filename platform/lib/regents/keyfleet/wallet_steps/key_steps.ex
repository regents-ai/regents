defmodule Regents.Keyfleet.WalletSteps.KeySteps do
  @moduledoc """
  The steps of a key's own buttons: buying the next key, asking again for a
  key's random draw or ending a wait for it that ran out, claiming what a
  key has earned, claiming a Regents Club key waiting for its Pass's holder,
  claiming for every key a wallet holds or holds a shard of at once, marking
  keys present, every key or only the idle ones, issuing, renewing and ending
  shards, and turning agent voting on or off.
  `Regents.Keyfleet.WalletSteps.Build` describes what every builder answers.

  Pages and requests name a fleet's Keys by number; every step names them by
  their id in the one Key collection, `Fleet.onchain_token_id/2`.
  """

  alias RegentChain.{Call, Review}
  alias Regents.Keyfleet.Fleets.{Fleet, Presets}
  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.Treasury
  alias Regents.Keyfleet.WalletSteps.{Build, Reads, Typed}

  # How long a purchase may take to reach the chain, counted from the latest
  # block's own clock, so a wallet's computer running fast or slow doesn't
  # shorten or stretch it.
  @purchase_seconds 600
  # How far above the next Key's price, in percent, a purchase may still go
  # through: Keys sold first in a rush move the price up a little each, and
  # the buyer gets the next Key left at or under this.
  @purchase_headroom_percent 5
  # The most a purchase may cost is rounded up to a whole cent.
  @cent 10_000
  # The approval a buyer who ticks Unlimited gives: the most a USDC allowance
  # can hold.
  @unlimited 2 ** 256 - 1
  # A key's seed before its random draw arrives.
  @no_seed "0x" <> String.duplicate("0", 64)
  # How long a renewed shard lasts, in days.
  @renew_days 30
  # How long a presence lasts, in seconds.
  @presence_seconds 172_800
  # How long an accepted request for a key's draw waits before anyone may
  # end it, in seconds (`KeyfleetKeys.REVEAL_TIMEOUT`).
  @reveal_timeout_seconds 86_400

  @doc false
  def steps(:buy, request) do
    if Presets.given?(request.fleet.id),
      do: {:problem, :not_for_sale, %{}},
      else: buy(request)
  end

  # Asking again for a key's random draw, which anyone may do while its
  # request was refused: it has no seed, and no request was ever accepted.
  # And ending the wait for a draw that hasn't come 24 hours after its
  # request was accepted, which anyone may do too: the key then never draws.
  # A key dealt its card by number never draws, and the contract refuses both.
  def steps(:reveal, %{fleet: fleet, token_id: token_id}) do
    figures = %{token_id: token_id}
    onchain = Fleet.onchain_token_id(fleet, token_id)

    steps = [
      Review.step(
        "reveal",
        fleet.keys_address,
        Call.encode("requestReveal(uint256)", [onchain])
      ),
      Review.step(
        "expire_reveal",
        fleet.keys_address,
        Call.encode("expireReveal(uint256)", [onchain])
      )
    ]

    if Fleet.dealt?(fleet, token_id),
      do: {:ok, steps, Map.put(figures, :blocked, both(:dealt_by_number))},
      else: reveal(fleet, onchain, steps, figures)
  end

  # One step for each token the ledger pays keys in: it settles the key to
  # its holder and pays the holder, and the signer's own credit when the
  # signer is the key's agent rather than its holder.
  def steps(:claim, %{fleet: fleet, signer: signer, token_id: token_id}) do
    figures = %{token_id: token_id, waiting: []}

    with {:ok, reads} <- Reads.at_head(),
         {:ok, assets} <-
           Reads.one(reads, fleet.rewards_address, "rewardAssets()", [], {:array, :address}),
         {:ok, %{^token_id => {holder, allowed?}}} when is_binary(holder) <-
           Reads.acting(reads, fleet, signer, [token_id], "isActive"),
         {:ok, waiting} <-
           Reads.each(assets, &waiting(reads, fleet, &1, token_id, holder, signer)) do
      steps =
        Enum.map(
          waiting,
          &Review.step(
            "claim-#{&1.asset}",
            fleet.rewards_address,
            Call.encode("claim(uint256[],address[])", [
              [Fleet.onchain_token_id(fleet, token_id)],
              [&1.asset]
            ])
          )
        )

      blocked =
        for entry <- waiting, reason = claim_blocked(allowed?, entry), into: %{} do
          {"claim-#{entry.asset}", reason}
        end

      {:ok, steps,
       %{token_id: token_id, holder: holder, waiting: named(fleet, waiting), blocked: blocked}}
    else
      _unread -> {:problem, :unread, figures}
    end
  end

  # One step for each token the ledger pays keys in, claiming for every key
  # the signer holds or holds an active shard of at once (`Build.own_keys/3`):
  # it settles each key to its holder and pays each holder, and the signer's
  # own credit. Only keys the signer may act for are named, since the ledger
  # refuses the whole claim for any other. A token with nothing waiting for
  # any of them, or for the signer, is certain to be refused, unless the chain
  # didn't say which Keys reached the signer lately.
  def steps(:claim_all, %{fleet: fleet, signer: signer}) do
    with {:ok, reads} <- Reads.at_head(),
         {candidates, unread} = Build.own_keys(reads, fleet, signer),
         {:ok, assets} <-
           Reads.one(reads, fleet.rewards_address, "rewardAssets()", [], {:array, :address}),
         {:ok, standing} <- Reads.acting(reads, fleet, signer, candidates, "isActive"),
         keys = for(key <- candidates, match?({_holder, true}, standing[key]), do: key),
         payees = Enum.uniq([signer | Enum.map(keys, &elem(standing[&1], 0))]),
         {:ok, waiting} <-
           Reads.each(assets, &waiting_for_keys(reads, fleet, &1, keys, payees)) do
      onchain = Enum.map(keys, &Fleet.onchain_token_id(fleet, &1))

      steps =
        Enum.map(
          waiting,
          &Review.step(
            "claim-#{&1.asset}",
            fleet.rewards_address,
            Call.encode("claim(uint256[],address[])", [onchain, [&1.asset]])
          )
        )

      blocked =
        for %{asset: asset, amount: 0} <- waiting,
            unread == nil,
            into: %{},
            do: {"claim-#{asset}", :nothing_to_claim}

      {:ok, steps, %{keys: keys, waiting: named(fleet, waiting), blocked: blocked}, unread}
    else
      _unread -> {:problem, :unread, %{keys: [], waiting: []}}
    end
  end

  # Taking Regents Club Key N from the claims contract, where it waits for
  # whoever holds Regents Club Pass N, with everything it earned while it
  # waited, in every asset at once, paid to the same wallet. Certain to fail once the Key has left the
  # contract, while the signer doesn't hold that Pass, and for good once the
  # Pass is burned, which the Pass collection then refuses to name a holder of.
  # Only a Regents Club Key waits there: the contract's claim(N) always moves
  # Club Key N, so any other fleet's Key gets no step.
  def steps(:club_claim, %{fleet: fleet, signer: signer, token_id: token_id}) do
    figures = %{token_id: token_id}
    claims = fleet.club_claims_address

    with :ok <- club(fleet),
         {:ok, reads} <- Reads.at_head(),
         {:ok, holder} <- Reads.holder(reads, fleet, token_id),
         {:ok, pass} <- Reads.one(reads, claims, "PASS()", [], :address),
         {:ok, pass_holder} <- pass_holder(reads, pass, token_id) do
      blocked =
        cond do
          holder != claims -> %{"club-claim" => :club_claimed}
          pass_holder == nil -> %{"club-claim" => :pass_burned}
          pass_holder != signer -> %{"club-claim" => :not_pass_holder}
          true -> %{}
        end

      step =
        Review.step(
          "club-claim",
          claims,
          Call.encode("claim(uint256,address)", [token_id, signer])
        )

      {:ok, [step], Map.put(figures, :blocked, blocked)}
    else
      {:problem, :not_club} -> {:problem, :not_club, figures}
      _unread -> {:problem, :unread, figures}
    end
  end

  # Marking Keys present: the one Key a Key's page is about, or every Key the
  # signer holds or holds an active shard of (`Build.own_keys/3`). A Key's
  # page shows whether its Key is present whoever is looking. A Key sold less
  # than two days ago can't be marked yet, and the vote contract refuses a
  # call naming one, so only the Keys old enough are named; with none old
  # enough the press is certain to fail. A visitor holds no Keys.
  def steps(:present, %{fleet: fleet, signer: signer, token_id: token_id}) do
    figures = %{keys: []}

    with {:ok, reads} <- Reads.at_head(),
         {candidates, unread} = present_candidates(reads, fleet, signer, token_id),
         {:ok, standing} <- Reads.acting(reads, fleet, signer, candidates, "isActive"),
         keys = for(key <- candidates, match?({_holder, true}, standing[key]), do: key),
         {:ok, presence} <-
           Reads.each(if(token_id, do: [token_id], else: keys), &presence(reads, fleet, &1)) do
      ready = for %{token_id: key, mature?: true} <- presence, key in keys, do: key

      {:ok, [present_step(fleet, ready)],
       %{
         keys: Enum.map(presence, &Map.delete(&1, :mature?)),
         ready: ready,
         blocked: present_blocked(keys, ready, token_id, unread)
       }, unread}
    else
      _unread -> {:problem, :unread, figures}
    end
  end

  # Marking present only the signer's idle Keys: those it holds that are old
  # enough and not present at the latest block, so none is renewed. A fleet's
  # page offers it while its holder's Keys are idle. A Key the signer holds a
  # shard of is its holder's to mark. With none idle the press is certain to
  # fail.
  def steps(:present_idle, %{fleet: fleet, signer: signer}) do
    with {:ok, reads} <- Reads.at_head(),
         {candidates, unread} = present_candidates(reads, fleet, signer, nil),
         {:ok, holders} <- Reads.each(candidates, &Reads.holder(reads, fleet, &1)),
         held = for({key, ^signer} <- Enum.zip(candidates, holders), do: key),
         {:ok, presence} <- Reads.each(held, &presence(reads, fleet, &1)) do
      idle = for %{token_id: key, until: nil, mature?: true} <- presence, do: key
      figures = %{keys: idle, blocked: idle_blocked(held, idle, unread)}
      {:ok, [present_step(fleet, idle)], figures, unread}
    else
      _unread -> {:problem, :unread, %{keys: []}}
    end
  end

  # Shards of the typed keys for the typed wallet and days. Issuing again to
  # a wallet that holds a shard of a key renews it from now.
  def steps(:issue_shard, %{fleet: fleet, signer: signer, inputs: inputs}) do
    with {:ok, keys} <- Build.typed(inputs, "keys", &Typed.keys/1, %{}),
         {:ok, wallet} <-
           Build.typed(inputs, "wallet", &Typed.address(&1, :shard_wallet_unreadable), %{
             keys: keys
           }),
         figures = %{keys: keys, wallet: wallet},
         {:ok, days} <- Build.typed(inputs, "days", &Typed.days/1, figures),
         figures = Map.put(figures, :days, days),
         {:ok, reads} <- reads(figures),
         {:ok, owned?} <- owned?(reads, fleet, signer, keys, figures) do
      blocked =
        cond do
          wallet == signer -> %{"issue" => :own_wallet}
          not owned? -> %{"issue" => :not_your_key}
          true -> %{}
        end

      {:ok, [Review.step("issue", fleet.shards_address, issue(fleet, keys, wallet, days))],
       Map.put(figures, :blocked, blocked)}
    end
  end

  # For each of the key's active shards, ending it now and renewing it.
  def steps(:end_shard, %{fleet: fleet, signer: signer, token_id: token_id}) do
    wallets = fleet.id |> Keys.active_shards_of_keys!([token_id]) |> Enum.map(& &1.wallet)
    figures = %{token_id: token_id, wallets: wallets, renew_days: @renew_days}

    with {:ok, reads} <- Reads.at_head(),
         {:ok, holder} <- Reads.holder(reads, fleet, token_id),
         {:ok, active} <-
           Reads.each(
             wallets,
             &Reads.one(
               reads,
               fleet.shards_address,
               "isActive(uint256,address)",
               [Fleet.onchain_token_id(fleet, token_id), &1],
               :bool
             )
           ) do
      steps =
        Enum.flat_map(wallets, fn wallet ->
          [
            Review.step(
              "end-#{wallet}",
              fleet.shards_address,
              Call.encode("end(uint256[],address)", [
                [Fleet.onchain_token_id(fleet, token_id)],
                wallet
              ])
            ),
            Review.step(
              "renew-#{wallet}",
              fleet.shards_address,
              issue(fleet, [token_id], wallet, @renew_days)
            )
          ]
        end)

      blocked =
        wallets
        |> Enum.zip(active)
        |> Enum.flat_map(fn {wallet, active?} ->
          [
            {"end-#{wallet}", end_blocked(active?, signer in [holder, wallet])},
            {"renew-#{wallet}", if(signer != holder, do: :not_your_key)}
          ]
        end)
        |> Enum.reject(fn {_step, reason} -> is_nil(reason) end)
        |> Map.new()

      {:ok, steps, Map.put(figures, :blocked, blocked)}
    else
      _unread -> {:problem, :unread, figures}
    end
  end

  # Whether the typed keys' shards may vote them and propose with them, and
  # which of them may now.
  def steps(:agent_voting, %{fleet: fleet, signer: signer, inputs: inputs}) do
    with {:ok, keys} <- Build.typed(inputs, "keys", &Typed.keys/1, %{}),
         figures = %{keys: keys, voting: []},
         {:ok, reads} <- reads(figures),
         {:ok, owned?} <- owned?(reads, fleet, signer, keys, figures),
         {:ok, voting} <- agent_voting_on(reads, fleet, keys, figures) do
      blocked = if owned?, do: %{}, else: %{"on" => :not_your_key, "off" => :not_your_key}

      {:ok,
       [
         Review.step("on", fleet.shards_address, agent_voting(fleet, keys, true)),
         Review.step("off", fleet.shards_address, agent_voting(fleet, keys, false))
       ], %{keys: keys, voting: voting, blocked: blocked}}
    end
  end

  @doc "How long a purchase step stays good after it is built, in seconds."
  def purchase_seconds, do: @purchase_seconds

  defp club(fleet), do: if(Presets.given?(fleet.id), do: :ok, else: {:problem, :not_club})

  # The Keys a presence step covers: the one named, else the signer's own.
  defp present_candidates(_reads, _fleet, _signer, token_id) when is_integer(token_id),
    do: {[token_id], nil}

  defp present_candidates(_reads, _fleet, nil, nil), do: {[], nil}
  defp present_candidates(reads, fleet, signer, nil), do: Build.own_keys(reads, fleet, signer)

  defp present_blocked([], _ready, token_id, _unread) when is_integer(token_id),
    do: %{"present" => :not_your_key}

  # Only a list of the signer's Keys brought up to the head says it has none
  # to mark; one the chain didn't bring up holds no press back.
  defp present_blocked(_keys, _ready, _token_id, :unread), do: %{}
  defp present_blocked([], _ready, nil, nil), do: %{"present" => :no_keys}
  defp present_blocked(_keys, [], _token_id, nil), do: %{"present" => :too_new}
  defp present_blocked(_keys, _ready, _token_id, nil), do: %{}

  defp idle_blocked(_held, _idle, :unread), do: %{}
  defp idle_blocked([], _idle, nil), do: %{"present" => :no_keys}
  defp idle_blocked(_held, [], nil), do: %{"present" => :none_idle}
  defp idle_blocked(_held, _idle, nil), do: %{}

  defp present_step(fleet, keys) do
    call = Call.encode("present(uint256[])", [onchain(fleet, keys)])
    Review.step("present", fleet.votes_address, call)
  end

  # The next Key, at its price, bought from the fleet's manager, which takes
  # the USDC. How many Keys are sold, the next one's price and when the
  # fleet's sales open are all read from the chain at the latest block, so a
  # Key sold since the page last heard is already counted, and the page names
  # the Key and price from these same figures. The manager refuses to price
  # the next Key only once every Key is sold (Regents Club Keys, never priced,
  # are turned away before this), so a refusal means there is nothing left to
  # buy. The purchase never names a Key: the manager sells whichever Key is
  # next when it lands, at that Key's price. So a buyer who loses a rush for
  # the Key on offer gets the next one left, as long as its price is within
  # the most the purchase names, the price plus @purchase_headroom_percent;
  # past that it is refused and no USDC is taken. The wallet approves that
  # most when its USDC allowance to the manager is below it, or without limit
  # when the buyer ticks Unlimited, and until it does the purchase is certain
  # to fail, as it is before the fleet's sales open.
  # Founding fleets ask nothing of buyers, so the purchase carries no proof.
  # A visitor sees the same figures, with no allowance and nothing to send.
  defp buy(%{fleet: fleet, signer: signer, inputs: inputs}) do
    unlimited? = Build.field(inputs, "unlimited") == "true"
    manager = &Reads.one(&1, fleet.manager_address, &2, [], {:uint, 256})

    with {:ok, reads} <- Reads.at_head(),
         {:ok, minted} <- manager.(reads, "totalMinted()") do
      case manager.(reads, "nextPrice()") do
        {:ok, price} ->
          offer(reads, fleet, signer, unlimited?, %{token_id: minted + 1, price: price})

        {:error, :reverted} ->
          {:problem, :sold_out, %{max_supply: minted}}

        {:error, _unread} ->
          {:problem, :unread, %{approve?: nil}}
      end
    else
      _unread -> {:problem, :unread, %{approve?: nil}}
    end
  end

  defp offer(reads, fleet, signer, unlimited?, %{price: price} = figures) do
    with {:ok, opens_at} <-
           Reads.one(
             reads,
             fleet.keys_address,
             "salesOpenAt(uint256)",
             [fleet.chain_fleet_id],
             {:uint, 64}
           ),
         {:ok, allowance} <- allowance(reads, fleet, signer) do
      now = DateTime.to_unix(Reads.now(reads))
      max_price = max_price(price)
      approve? = allowance != nil and allowance < max_price

      blocked =
        cond do
          opens_at == 0 or now < opens_at ->
            %{"buy" => opening(opens_at)}

          approve? ->
            %{"buy" => :approve_usdc_first}

          true ->
            %{}
        end

      approval = if unlimited?, do: @unlimited, else: max_price

      {:ok, purchase(fleet, signer, approval, max_price, now + @purchase_seconds, approve?),
       Map.merge(figures, %{max_price: max_price, approve?: approve?, blocked: blocked})}
    else
      _unread -> {:problem, :unread, Map.put(figures, :approve?, nil)}
    end
  end

  defp max_price(price) do
    whole = 100 * @cent
    div(price * (100 + @purchase_headroom_percent) + whole - 1, whole) * @cent
  end

  # The wallet's USDC allowance to the manager; a visitor has none to read.
  defp allowance(_reads, _fleet, nil), do: {:ok, nil}

  defp allowance(reads, fleet, signer),
    do:
      Reads.one(
        reads,
        fleet.usdc_address,
        "allowance(address,address)",
        [signer, fleet.manager_address],
        {:uint, 256}
      )

  defp purchase(_fleet, nil, _approval, _max_price, _deadline, _approve?), do: []

  defp purchase(fleet, signer, approval, max_price, deadline, approve?) do
    approve =
      Review.step(
        "approve",
        fleet.usdc_address,
        Call.encode("approve(address,uint256)", [fleet.manager_address, approval])
      )

    buy =
      Review.step(
        "buy",
        fleet.manager_address,
        Call.encode("purchase(address,uint256,uint256,bytes32[])", [
          signer,
          max_price,
          deadline,
          []
        ])
      )

    if approve?, do: [approve, buy], else: [buy]
  end

  # Before a fleet's sales open, its opening time when one is set.
  defp opening(0), do: :sales_not_open
  defp opening(opens_at), do: {:opens_at, DateTime.from_unix!(opens_at)}

  # What a claim of one asset would pay: what the key has accrued, which
  # settles to its holder, the holder's credit, and the signer's own when the
  # signer isn't the holder.
  defp waiting(reads, fleet, asset, token_id, holder, signer) do
    credit =
      &Reads.one(
        reads,
        fleet.rewards_address,
        "credits(address,address)",
        [asset, &1],
        {:uint, 256}
      )

    with {:ok, accrued} <-
           Reads.one(
             reads,
             fleet.rewards_address,
             "accrued(address,uint256)",
             [asset, Fleet.onchain_token_id(fleet, token_id)],
             {:uint, 256}
           ),
         {:ok, held} <- credit.(holder),
         {:ok, own} <- if(signer == holder, do: {:ok, 0}, else: credit.(signer)) do
      {:ok, %{asset: asset, amount: accrued + held + own}}
    end
  end

  # What a claim of one asset for many keys would pay: what each key has
  # accrued, which settles to its holder, and the credit of each payee, the
  # signer and every holder of those keys.
  defp waiting_for_keys(reads, fleet, asset, keys, payees) do
    accrued =
      &Reads.one(
        reads,
        fleet.rewards_address,
        "accrued(address,uint256)",
        [asset, Fleet.onchain_token_id(fleet, &1)],
        {:uint, 256}
      )

    credit =
      &Reads.one(
        reads,
        fleet.rewards_address,
        "credits(address,address)",
        [asset, &1],
        {:uint, 256}
      )

    with {:ok, accrued} <- Reads.each(keys, accrued),
         {:ok, credits} <- Reads.each(payees, credit) do
      {:ok, %{asset: asset, amount: Enum.sum(accrued) + Enum.sum(credits)}}
    end
  end

  defp claim_blocked(false, _entry), do: :not_your_key
  defp claim_blocked(true, %{amount: 0}), do: :nothing_to_claim
  defp claim_blocked(true, _entry), do: nil

  defp end_blocked(false, _may_end?), do: :shard_ended
  defp end_blocked(true, false), do: :not_your_key
  defp end_blocked(true, true), do: nil

  # Each amount with its token's symbol and decimals, as the fleet's balances
  # name them; both nil for a token that hasn't said.
  defp named(fleet, waiting) do
    known = Map.new(Treasury.payable_assets(fleet), &{&1.address, &1})

    Enum.map(waiting, fn %{asset: asset} = entry ->
      known
      |> Map.get(asset, %{symbol: nil, decimals: nil, usdc?: false, known?: false})
      |> Map.take([:symbol, :decimals, :usdc?, :known?])
      |> Map.merge(entry)
    end)
  end

  # The Key with when its presence lapses, nil when it isn't present, and
  # whether it is old enough to be marked present.
  defp presence(reads, fleet, key) do
    onchain = Fleet.onchain_token_id(fleet, key)

    with {:ok, active?} <-
           Reads.one(reads, fleet.votes_address, "isActive(uint256)", [onchain], :bool),
         {:ok, from} <-
           Reads.one(reads, fleet.votes_address, "presentFrom(uint256)", [onchain], {:uint, 64}),
         {:ok, matures_at} <- matures_at(reads, fleet, onchain) do
      now = DateTime.to_unix(Reads.now(reads))

      {:ok,
       %{
         token_id: key,
         until: if(active?, do: DateTime.from_unix!(from + @presence_seconds)),
         mature?: matures_at != nil and matures_at <= now
       }}
    end
  end

  # When a Key may first take part, nil for one not sold yet, which the vote
  # contract refuses to date.
  defp matures_at(reads, fleet, onchain) do
    case Reads.one(reads, fleet.votes_address, "maturesAt(uint256)", [onchain], {:uint, 64}) do
      {:error, :reverted} -> {:ok, nil}
      answer -> answer
    end
  end

  # Whether the signer holds every key named, read at the head.
  defp owned?(reads, fleet, signer, keys, figures) do
    case Reads.each(keys, &Reads.holder(reads, fleet, &1)) do
      {:ok, holders} -> {:ok, Enum.all?(holders, &(&1 == signer))}
      {:error, _reason} -> {:problem, :unread, figures}
    end
  end

  # The keys whose shards may vote now, read at the head.
  defp agent_voting_on(reads, fleet, keys, figures) do
    case Reads.each(
           keys,
           &Reads.one(
             reads,
             fleet.shards_address,
             "agentVoting(uint256)",
             [Fleet.onchain_token_id(fleet, &1)],
             :bool
           )
         ) do
      {:ok, on} -> {:ok, for({key, true} <- Enum.zip(keys, on), do: key)}
      {:error, _reason} -> {:problem, :unread, figures}
    end
  end

  defp reads(figures) do
    case Reads.at_head() do
      {:ok, reads} -> {:ok, reads}
      {:error, _reason} -> {:problem, :unread, figures}
    end
  end

  defp issue(fleet, keys, wallet, days),
    do: Call.encode("issue(uint256[],address,uint16)", [onchain(fleet, keys), wallet, days])

  defp agent_voting(fleet, keys, on),
    do: Call.encode("setAgentVoting(uint256[],bool)", [onchain(fleet, keys), on])

  defp onchain(fleet, keys), do: Enum.map(keys, &Fleet.onchain_token_id(fleet, &1))

  # Whether the chain has a seed for the key, a request waiting, or a wait
  # that was ended, and whether its fleet's deck is set on the chain yet, as
  # the contract checks. The two calls need nothing from the chain, so when it
  # doesn't answer they are still built, neither held back, and the build says
  # the chain couldn't be read.
  defp reveal(fleet, onchain, steps, figures) do
    with {:ok, reads} <- Reads.at_head(),
         {:ok, [_manager, _preset, _type, _size, deck_hash]} <-
           Reads.many(
             reads,
             fleet.keys_address,
             "fleet(uint256)",
             [fleet.chain_fleet_id],
             [:address, {:uint, 8}, {:uint, 32}, {:uint, 32}, :bytes32]
           ),
         {:ok, seed} <-
           Reads.one(reads, fleet.keys_address, "revealSeed(uint256)", [onchain], :bytes32),
         {:ok, requested_at} <-
           Reads.one(
             reads,
             fleet.keys_address,
             "revealRequestedAt(uint256)",
             [onchain],
             {:uint, 64}
           ),
         {:ok, expired?} <-
           Reads.one(reads, fleet.keys_address, "revealExpired(uint256)", [onchain], :bool) do
      blocked =
        cond do
          seed != @no_seed ->
            both(:revealed)

          expired? ->
            both(:reveal_expired)

          requested_at != 0 ->
            asked(Reads.now(reads), requested_at)

          deck_hash == @no_seed ->
            %{"reveal" => :deck_not_set, "expire_reveal" => :no_draw_waiting}

          true ->
            %{"expire_reveal" => :no_draw_waiting}
        end

      {:ok, steps, Map.put(figures, :blocked, blocked)}
    else
      _unread -> {:ok, steps, figures, :unread}
    end
  end

  defp both(reason), do: %{"reveal" => reason, "expire_reveal" => reason}

  # A waiting request is never asked again; its wait may be ended from 24
  # hours after it was accepted, by the latest block's own clock.
  defp asked(now, requested_at) do
    ends_from = DateTime.from_unix!(requested_at + @reveal_timeout_seconds)

    if DateTime.before?(now, ends_from),
      do: %{"reveal" => :reveal_requested, "expire_reveal" => {:expire_from, ends_from}},
      else: %{"reveal" => :reveal_requested}
  end

  # Who holds Regents Club Pass `pass_id`, or nil once it is burned.
  defp pass_holder(reads, pass, pass_id) do
    case Reads.one(reads, pass, "ownerOf(uint256)", [pass_id], :address) do
      {:error, :reverted} -> {:ok, nil}
      answer -> answer
    end
  end
end
