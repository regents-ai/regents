defmodule Regents.Autolaunch.Exposure.Chain do
  @moduledoc """
  What an `ExposureSeriesV1`, its oracle, its legs and their pools say at one
  block. Exposure keeps no records of its own: every figure a page or an agent
  sees is read here, so it matches the chain after any reload.

  Reads are batched through Multicall3 (`Regents.Autolaunch.Chain.Multicall`)
  at the block's own hash so one series read takes at most three `eth_call`s
  rather than dozens of concurrent individual requests.

  A series reading has the series' fixed terms (stock, legs, oracle, schedule,
  cap, terms hash), its state (status, how many prints are applied, the last
  price and both ledgers, the stock it accounts for and holds), every applied
  print with the feed round it came from, the next print to apply, and each
  leg's pool price in USDC when its pool exists.
  """

  alias RegentChain.Call
  alias Regents.Autolaunch.Chain.{Abi, Multicall, Rpc}
  alias Regents.Autolaunch.Exposure.Ledger
  alias Regents.Autolaunch.Lab

  @statuses %{0 => :pending, 1 => :active, 2 => :ended}
  @end_reasons %{
    0 => nil,
    1 => :maturity,
    2 => :overnight_depleted,
    3 => :session_depleted,
    4 => :missing_print
  }
  @record_delay 3_600

  @doc "The read options and latest block of the Base deployment Exposure runs on."
  def latest(lab) do
    opts = Lab.rpc_opts(lab, "autolaunch exposure")
    with {:ok, block} <- Rpc.latest_block(opts), do: {:ok, block, opts}
  end

  @doc "One series as it stands at `block`, with its legs' pool prices from `config`."
  def series(address, config, block, opts) do
    with {:ok, head} <- read_head(address, block, opts),
         {:ok, details} <- read_details(address, head, config, block, opts),
         {:ok, prints, pools} <- read_prints_and_pools(head, details, config, block, opts) do
      terms = %{
        asset: head.asset,
        oracle: head.oracle,
        feed_id: head.feed_id,
        terms_hash: head.terms_hash,
        max_report_delay: head.max_report_delay,
        deposit_cap: head.deposit_cap,
        boundaries: details.boundaries,
        feed: details.feed,
        phase: details.phase,
        stock: details.stock,
        overnight: details.overnight,
        session: details.session
      }

      state = %{
        status: head.status,
        end_reason: head.end_reason,
        settled: head.settled,
        price: head.price,
        night: head.night,
        day: head.price - head.night,
        accounted: head.accounted,
        held: details.held,
        supply: %{overnight: details.overnight_supply, session: details.session_supply}
      }

      {:ok,
       terms
       |> Map.merge(state)
       |> Map.merge(%{
         address: address,
         block: block.number,
         now: block.timestamp,
         prints: prints,
         next: next(terms, state, prints, block),
         pools: pools
       })}
    end
  end

  # Batch 1: every direct view on the series contract itself (fixed terms + live state).
  defp read_head(address, block, opts) do
    reads = [
      {address, Call.encode("asset()", [])},
      {address, Call.encode("overnight()", [])},
      {address, Call.encode("session()", [])},
      {address, Call.encode("oracle()", [])},
      {address, Call.encode("feedId()", [])},
      {address, Call.encode("termsHash()", [])},
      {address, Call.encode("maxReportDelay()", [])},
      {address, Call.encode("depositCap()", [])},
      {address, Call.encode("boundaryCount()", [])},
      {address, Call.encode("status()", [])},
      {address, Call.encode("endReason()", [])},
      {address, Call.encode("settled()", [])},
      {address, Call.encode("lastPriceWad()", [])},
      {address, Call.encode("overnightLedgerWad()", [])},
      {address, Call.encode("accountedAssets()", [])}
    ]

    with {:ok,
          [
            asset_raw,
            overnight_raw,
            session_raw,
            oracle_raw,
            feed_id_raw,
            terms_hash_raw,
            max_delay_raw,
            deposit_cap_raw,
            boundary_count_raw,
            status_raw,
            end_reason_raw,
            settled_raw,
            price_raw,
            night_raw,
            accounted_raw
          ]} <- Multicall.read(reads, block, opts),
         {:ok, asset} <- decode_address(asset_raw),
         {:ok, overnight} <- decode_address(overnight_raw),
         {:ok, session} <- decode_address(session_raw),
         {:ok, oracle} <- decode_address(oracle_raw),
         {:ok, feed_id} <- decode_word_hex(feed_id_raw),
         {:ok, terms_hash} <- decode_word_hex(terms_hash_raw),
         {:ok, max_report_delay} <- decode_uint(max_delay_raw),
         {:ok, deposit_cap} <- decode_uint(deposit_cap_raw),
         {:ok, boundary_count} <- decode_uint(boundary_count_raw),
         {:ok, status_code} <- decode_uint(status_raw),
         {:ok, status} <- fetch_enum(@statuses, status_code),
         {:ok, end_reason_code} <- decode_uint(end_reason_raw),
         {:ok, end_reason} <- fetch_enum(@end_reasons, end_reason_code),
         {:ok, settled} <- decode_uint(settled_raw),
         {:ok, price} <- decode_uint(price_raw),
         {:ok, night} <- decode_uint(night_raw),
         {:ok, accounted} <- decode_uint(accounted_raw) do
      {:ok,
       %{
         asset: asset,
         overnight: overnight,
         session: session,
         oracle: oracle,
         feed_id: feed_id,
         terms_hash: terms_hash,
         max_report_delay: max_report_delay,
         deposit_cap: deposit_cap,
         boundary_count: boundary_count,
         status: status,
         end_reason: end_reason,
         settled: settled,
         price: price,
         night: night,
         accounted: accounted
       }}
    end
  end

  # Batch 2: boundary timestamps, oracle feed/phase, ERC-20 metadata, supplies, held stock,
  # and both Aerodrome pool addresses in one Multicall3 request.
  defp read_details(address, head, config, block, opts) do
    boundary_reads =
      if head.boundary_count == 0 do
        []
      else
        for index <- 0..(head.boundary_count - 1) do
          {address, Call.encode("boundaries(uint256)", [index])}
        end
      end

    meta_reads = [
      {head.oracle, Call.encode("feed()", [])},
      {head.oracle, Call.encode("phase()", [])},
      {head.asset, Call.encode("symbol()", [])},
      {head.asset, Call.encode("name()", [])},
      {head.asset, Call.encode("decimals()", [])},
      {head.overnight, Call.encode("symbol()", [])},
      {head.overnight, Call.encode("name()", [])},
      {head.overnight, Call.encode("decimals()", [])},
      {head.session, Call.encode("symbol()", [])},
      {head.session, Call.encode("name()", [])},
      {head.session, Call.encode("decimals()", [])},
      {head.asset, Abi.encode_erc20("balance_of", [address])},
      {head.overnight, Call.encode("totalSupply()", [])},
      {head.session, Call.encode("totalSupply()", [])},
      {config.pool_factory,
       Call.encode("getPool(address,address,bool)", [head.overnight, config.usdc, false])},
      {config.pool_factory,
       Call.encode("getPool(address,address,bool)", [head.session, config.usdc, false])}
    ]

    with {:ok, answers} <- Multicall.read(boundary_reads ++ meta_reads, block, opts),
         {boundary_raws,
          [
            feed_raw,
            phase_raw,
            stock_sym,
            stock_name,
            stock_dec,
            on_sym,
            on_name,
            on_dec,
            ses_sym,
            ses_name,
            ses_dec,
            held_raw,
            on_supply_raw,
            ses_supply_raw,
            on_pool_raw,
            ses_pool_raw
          ]} = Enum.split(answers, head.boundary_count),
         {:ok, boundaries} <- decode_each(boundary_raws, &decode_uint/1),
         {:ok, feed} <- decode_address(feed_raw),
         {:ok, phase} <- decode_uint(phase_raw),
         {:ok, stock} <- decode_token(head.asset, stock_sym, stock_name, stock_dec),
         {:ok, overnight} <- decode_token(head.overnight, on_sym, on_name, on_dec),
         {:ok, session} <- decode_token(head.session, ses_sym, ses_name, ses_dec),
         {:ok, held} <- decode_uint(held_raw),
         {:ok, overnight_supply} <- decode_uint(on_supply_raw),
         {:ok, session_supply} <- decode_uint(ses_supply_raw),
         {:ok, overnight_pool} <- decode_optional_address(on_pool_raw),
         {:ok, session_pool} <- decode_optional_address(ses_pool_raw) do
      {:ok,
       %{
         boundaries: boundaries,
         feed: feed,
         phase: phase,
         stock: stock,
         overnight: overnight,
         session: session,
         held: held,
         overnight_supply: overnight_supply,
         session_supply: session_supply,
         overnight_pool: overnight_pool,
         session_pool: session_pool
       }}
    end
  end

  # Batch 3: every applied print (`getPrint` + `sourceOf`) and `getReserves()` for existing pools.
  defp read_prints_and_pools(head, details, config, block, opts) do
    applied = details.boundaries |> Enum.take(head.settled) |> Enum.with_index()

    print_reads =
      Enum.flat_map(applied, fn {at, index} ->
        open? = rem(index, 2) == 1

        [
          {head.oracle, Call.encode("getPrint(bytes32,uint64,bool)", [head.feed_id, at, open?])},
          {head.oracle, Call.encode("sourceOf(uint64,bool)", [at, open?])}
        ]
      end)

    pool_specs =
      [
        {:overnight, details.overnight_pool, details.overnight},
        {:session, details.session_pool, details.session}
      ]

    existing_pools = Enum.filter(pool_specs, fn {_leg, addr, _tok} -> not is_nil(addr) end)

    reserve_reads =
      Enum.map(existing_pools, fn {_leg, pool_addr, _tok} ->
        {pool_addr, Call.encode("getReserves()", [])}
      end)

    all_reads = print_reads ++ reserve_reads

    with {:ok, answers} <-
           if(all_reads == [], do: {:ok, []}, else: Multicall.read(all_reads, block, opts)),
         {print_raws, reserve_raws} = Enum.split(answers, length(print_reads)),
         {:ok, recorded} <- decode_prints(applied, print_raws),
         {:ok, pool_prices} <- decode_pool_prices(existing_pools, reserve_raws, config.usdc) do
      steps = recorded |> Enum.map(& &1.price) |> Ledger.path()
      prints = Enum.zip_with(recorded, steps, &Map.merge(&1, Map.take(&2, [:night, :day])))

      pools =
        Map.new(pool_specs, fn {leg, addr, _tok} ->
          {leg, addr && %{address: addr, usdc_per_token: Map.get(pool_prices, leg)}}
        end)

      {:ok, prints, pools}
    end
  end

  @doc """
  The print the oracle recorded for boundary `index` at `at`, with its feed
  round, or `price: 0` while none is recorded.
  """
  def recorded(terms, at, index, block, opts) do
    open? = rem(index, 2) == 1

    reads = [
      {terms.oracle, Call.encode("getPrint(bytes32,uint64,bool)", [terms.feed_id, at, open?])},
      {terms.oracle, Call.encode("sourceOf(uint64,bool)", [at, open?])}
    ]

    with {:ok, [print_raw, source_raw]} <- Multicall.read(reads, block, opts),
         {:ok, [price, observed_at, finalized_at]} <- decode_words(print_raw, 3),
         {:ok, [round_id, updated_at]} <- decode_words(source_raw, 2) do
      {:ok,
       %{
         index: index,
         at: at,
         open?: open?,
         price: price,
         observed_at: observed_at,
         finalized_at: finalized_at,
         round_id: round_id,
         updated_at: updated_at
       }}
    end
  end

  # The print to apply next and when it can be recorded, or nil once ended.
  defp next(_terms, %{status: :ended}, _prints, _block), do: nil

  defp next(terms, state, _prints, block) do
    at = Enum.at(terms.boundaries, state.settled)

    %{
      index: state.settled,
      at: at,
      open?: rem(state.settled, 2) == 1,
      recordable_at: at + @record_delay,
      deadline: at + terms.max_report_delay,
      due?: block.timestamp >= at + @record_delay
    }
  end

  @doc """
  Each leg's pool against USDC on the Aerodrome factory, and its price for one
  whole leg token (USDC micro-units): the USDC it holds for each token it holds,
  before any trade moves it. Nil where there is no pool or a side is empty.
  """
  def pools(terms, config, block, opts) do
    reads = [
      {config.pool_factory,
       Call.encode("getPool(address,address,bool)", [terms.overnight.address, config.usdc, false])},
      {config.pool_factory,
       Call.encode("getPool(address,address,bool)", [terms.session.address, config.usdc, false])}
    ]

    with {:ok, [on_raw, ses_raw]} <- Multicall.read(reads, block, opts),
         {:ok, on_pool} <- decode_optional_address(on_raw),
         {:ok, ses_pool} <- decode_optional_address(ses_raw) do
      specs = [{:overnight, on_pool, terms.overnight}, {:session, ses_pool, terms.session}]
      read_pool_reserves(specs, config.usdc, block, opts)
    end
  end

  defp read_pool_reserves(specs, usdc, block, opts) do
    existing = Enum.filter(specs, fn {_leg, addr, _tok} -> not is_nil(addr) end)

    reserve_reads =
      Enum.map(existing, fn {_leg, addr, _tok} -> {addr, Call.encode("getReserves()", [])} end)

    with {:ok, reserve_raws} <- read_optional_batch(reserve_reads, block, opts),
         {:ok, prices} <- decode_pool_prices(existing, reserve_raws, usdc) do
      {:ok,
       Map.new(specs, fn {leg, addr, _tok} ->
         {leg, addr && %{address: addr, usdc_per_token: Map.get(prices, leg)}}
       end)}
    end
  end

  defp read_optional_batch([], _block, _opts), do: {:ok, []}
  defp read_optional_batch(reads, block, opts), do: Multicall.read(reads, block, opts)

  defp per_token(held, dollars, decimals) when held > 0 and dollars > 0,
    do: div(dollars * Integer.pow(10, decimals), held)

  defp per_token(_held, _dollars, _decimals), do: nil

  @doc """
  What `wallet` holds of the series' stock and legs, what it lets the series
  take of its stock, and the raw stock its legs would redeem for now: whole
  pairs before the end, every leg after it.
  """
  def holdings(series, wallet, block, opts) do
    reads = [
      {series.overnight.address, Abi.encode_erc20("balance_of", [wallet])},
      {series.session.address, Abi.encode_erc20("balance_of", [wallet])},
      {series.stock.address, Abi.encode_erc20("balance_of", [wallet])},
      {series.stock.address, Abi.encode_erc20("allowance", [wallet, series.address])}
    ]

    with {:ok, [on_raw, ses_raw, stock_raw, allow_raw]} <- Multicall.read(reads, block, opts),
         {:ok, overnight} <- decode_uint(on_raw),
         {:ok, session} <- decode_uint(ses_raw),
         {:ok, stock} <- decode_uint(stock_raw),
         {:ok, allowance} <- decode_uint(allow_raw) do
      {:ok,
       %{
         wallet: wallet,
         overnight: overnight,
         session: session,
         stock: stock,
         allowance: allowance,
         redeemable: redeemable(series, overnight, session)
       }}
    end
  end

  @doc """
  The amounts `redeem` takes from a holding of `overnight` and `session` now,
  and the raw stock it would pay: before the end, the whole pairs held; after
  it, every leg.
  """
  def redeemable(%{status: :ended} = series, overnight, session),
    do: %{
      overnight: overnight,
      session: session,
      paid: paid(series, overnight, session)
    }

  def redeemable(series, overnight, session) do
    pairs = min(overnight, session)
    %{overnight: pairs, session: pairs, paid: paid(series, pairs, pairs)}
  end

  @doc "The raw stock `redeem(overnight, session)` pays now, as the contract works it out."
  def paid(series, overnight, session),
    do: series |> owed(overnight, session) |> Ledger.paid(series.held, series.accounted)

  @doc """
  The raw stock the legs are owed before any cut for a seizure: whole pairs
  before the end, the frozen ledgers' share after it.
  """
  def owed(_series, 0, 0), do: 0

  def owed(%{status: :ended} = series, overnight, session),
    do: Ledger.owed(overnight, session, series.price, series.night)

  def owed(_series, pairs, pairs), do: pairs

  @doc """
  The round of the oracle's pinned feed phase in force at `at`: the last one
  updated at or before it, with when it was updated, or `:no_round`. Rounds of
  a phase count up from 1 and a missing round reads as zeros, so the search
  doubles until it finds a missing round, then halves.
  """
  def round_in_force(series, at, block, opts) do
    with {:ok, high} <- upper(series, 1, block, opts),
         {:ok, round} <- search(series, at, 0, high, block, opts),
         true <- round > 0 || {:error, :no_round},
         {:ok, updated_at} <- updated_at(series, round, block, opts),
         do: {:ok, %{round: round, updated_at: updated_at}}
  end

  defp upper(series, high, block, opts) do
    case updated_at(series, high, block, opts) do
      {:ok, 0} -> {:ok, high}
      {:ok, _updated} -> upper(series, high * 2, block, opts)
      error -> error
    end
  end

  # Rounds low+1 .. high-1 may exist; `low` is the last known in force at `at`.
  defp search(_series, _at, low, high, _block, _opts) when high - low <= 1, do: {:ok, low}

  defp search(series, at, low, high, block, opts) do
    mid = low + div(high - low, 2)

    case updated_at(series, mid, block, opts) do
      {:ok, updated} when updated != 0 and updated <= at ->
        search(series, at, mid, high, block, opts)

      {:ok, _later_or_missing} ->
        search(series, at, low, mid, block, opts)

      error ->
        error
    end
  end

  defp updated_at(series, round, block, opts) do
    round_id = Bitwise.bsl(series.phase, 64) + round

    with {:ok, [_round, _answer, _started, updated_at, _answered]} <-
           Rpc.call_words(
             series.feed,
             Call.encode("getRoundData(uint80)", [round_id]),
             block,
             5,
             opts
           ),
         do: {:ok, updated_at}
  end

  @doc """
  What trading one leg against USDC through the Aerodrome router takes from
  `wallet` now: its USDC and leg balances and what each lets the router take,
  and the leg's pool, or nil where it has none.
  """
  def trade_position(series, config, leg, wallet, block, opts) do
    token = Map.fetch!(series, leg).address

    reads = [
      {config.pool_factory,
       Call.encode("getPool(address,address,bool)", [token, config.usdc, false])},
      {config.usdc, Abi.encode_erc20("balance_of", [wallet])},
      {config.usdc, Abi.encode_erc20("allowance", [wallet, config.router])},
      {token, Abi.encode_erc20("balance_of", [wallet])},
      {token, Abi.encode_erc20("allowance", [wallet, config.router])}
    ]

    with {:ok, [pool_raw, usdc_raw, usdc_allow_raw, held_raw, leg_allow_raw]} <-
           Multicall.read(reads, block, opts),
         {:ok, pool} <- decode_optional_address(pool_raw),
         {:ok, usdc} <- decode_uint(usdc_raw),
         {:ok, usdc_allowance} <- decode_uint(usdc_allow_raw),
         {:ok, held} <- decode_uint(held_raw),
         {:ok, leg_allowance} <- decode_uint(leg_allow_raw) do
      {:ok,
       %{
         pool: pool,
         usdc: usdc,
         usdc_allowance: usdc_allowance,
         leg: held,
         leg_allowance: leg_allowance
       }}
    end
  end

  @doc """
  What `pool` pays out now for `amount` of `token_in`, as Aerodrome's own pool
  works it out, or nil while either side of the pool is empty.
  """
  def amount_out(pool, amount, token_in, block, opts) do
    with {:ok, [reserve0, reserve1, _last]} <-
           Rpc.call_words(pool, Call.encode("getReserves()", []), block, 3, opts) do
      if reserve0 == 0 or reserve1 == 0,
        do: {:ok, nil},
        else:
          Rpc.call_uint(
            pool,
            Call.encode("getAmountOut(uint256,address)", [amount, token_in]),
            block,
            opts
          )
    end
  end

  @doc "What `holder` holds of `token` at `block`, in its raw units."
  def token_balance(token, holder, block, opts),
    do: Rpc.call_uint(token, Abi.encode_erc20("balance_of", [holder]), block, opts)

  # Multicall3 decoders

  defp decode_token(address, symbol_raw, name_raw, decimals_raw) do
    with {:ok, symbol} <- decode_string(symbol_raw),
         {:ok, name} <- decode_string(name_raw),
         {:ok, decimals} <- decode_uint(decimals_raw) do
      {:ok, %{address: address, symbol: symbol, name: name, decimals: decimals}}
    end
  end

  defp decode_prints(applied, print_raws) do
    applied
    |> Enum.zip(Enum.chunk_every(print_raws, 2))
    |> Enum.reduce_while({:ok, []}, fn {{at, index}, [print_raw, source_raw]}, {:ok, acc} ->
      open? = rem(index, 2) == 1

      with {:ok, [price, observed_at, finalized_at]} <- decode_words(print_raw, 3),
           {:ok, [round_id, updated_at]} <- decode_words(source_raw, 2) do
        entry = %{
          index: index,
          at: at,
          open?: open?,
          price: price,
          observed_at: observed_at,
          finalized_at: finalized_at,
          round_id: round_id,
          updated_at: updated_at
        }

        {:cont, {:ok, [entry | acc]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  defp decode_pool_prices(existing_pools, reserve_raws, usdc) do
    existing_pools
    |> Enum.zip(reserve_raws)
    |> Enum.reduce_while({:ok, %{}}, fn {{leg, _pool_addr, token}, reserve_raw}, {:ok, acc} ->
      case decode_words(reserve_raw, 3) do
        {:ok, [reserve0, reserve1, _last]} ->
          {:cont, {:ok, Map.put(acc, leg, pool_price(token, usdc, reserve0, reserve1))}}

        error ->
          {:halt, error}
      end
    end)
  end

  # Aerodrome orders a pool's two tokens by address.
  defp pool_price(token, usdc, reserve0, reserve1) do
    {held, dollars} =
      if String.downcase(token.address) < String.downcase(usdc),
        do: {reserve0, reserve1},
        else: {reserve1, reserve0}

    per_token(held, dollars, token.decimals)
  end

  defp decode_each(items, decoder) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case decoder.(item) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp fetch_enum(table, code) do
    case Map.fetch(table, code) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :invalid_chain_response}
    end
  end

  defp decode_uint(<<value::256>>), do: {:ok, value}
  defp decode_uint(:reverted), do: {:error, :refused}
  defp decode_uint(_other), do: {:error, :invalid_chain_response}

  defp decode_address(<<0::96, bytes::binary-size(20)>>),
    do: {:ok, "0x" <> Base.encode16(bytes, case: :lower)}

  defp decode_address(:reverted), do: {:error, :refused}
  defp decode_address(_other), do: {:error, :invalid_chain_response}

  defp decode_optional_address(<<0::256>>), do: {:ok, nil}
  defp decode_optional_address(other), do: decode_address(other)

  defp decode_word_hex(<<bytes::binary-size(32)>>),
    do: {:ok, "0x" <> Base.encode16(bytes, case: :lower)}

  defp decode_word_hex(:reverted), do: {:error, :refused}
  defp decode_word_hex(_other), do: {:error, :invalid_chain_response}

  defp decode_words(bin, count) when is_binary(bin) and byte_size(bin) == count * 32,
    do: {:ok, for(<<word::256 <- bin>>, do: word)}

  defp decode_words(:reverted, _count), do: {:error, :refused}
  defp decode_words(_other, _count), do: {:error, :invalid_chain_response}

  defp decode_string(<<offset::256, _rest::binary>> = bin)
       when offset <= byte_size(bin) - 32 do
    case binary_part(bin, offset, byte_size(bin) - offset) do
      <<len::256, bytes::binary-size(len), _tail::binary>> ->
        if String.valid?(bytes), do: {:ok, bytes}, else: {:error, :invalid_chain_response}

      _malformed ->
        {:error, :invalid_chain_response}
    end
  end

  defp decode_string(:reverted), do: {:error, :refused}
  defp decode_string(_other), do: {:error, :invalid_chain_response}
end
