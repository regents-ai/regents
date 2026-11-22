defmodule Regents.Keyfleet.WalletSteps.MoneySteps do
  @moduledoc """
  The steps of a fleet's money that anyone may press: running the daily
  split, returning an advance, sending the protocol share owed to REGENT
  staking, and turning the USDC from Key sales into REGENT for the treasury.
  `Regents.Keyfleet.WalletSteps.Build` describes what every builder answers.

  The daily split's figures are its preview, read at the latest block the
  way the treasury works it out: for each asset it splits, the balance, the
  least it splits from, and what each key would get now.
  """

  alias RegentChain.{Call, Review}
  alias Regents.Keyfleet.Treasury
  alias Regents.Keyfleet.WalletSteps.{Build, Reads, Typed}

  # The least ETH the treasury splits from, as the treasury fixes it.
  @eth_threshold 50_000_000_000_000_000
  # The USDC token's decimals, which the manager refuses to be deployed
  # without.
  @usdc_decimals 6
  @usdc_unit 1_000_000
  # The most USDC the REGENT buyer turns in one piece.
  @piece_usdc 250_000_000

  @doc false
  def steps(:run_split, %{fleet: fleet}) do
    treasury = fleet.treasury_address
    uint = &Reads.one(&1, treasury, &2, [], {:uint, 256})

    with {:ok, reads} <- Reads.at_head(),
         {:ok, assets} <- Reads.one(reads, treasury, "splitAssets()", [], {:array, :address}),
         {:ok, bps} <- uint.(reads, "dailySplitBps()"),
         {:ok, last_run_at} <- uint.(reads, "lastRunAt()"),
         {:ok, next_run_at} <- uint.(reads, "nextRunAt()"),
         # The split pays only Keys sold at least 2 days ago, as the treasury
         # counts them.
         {:ok, keys} <-
           Reads.one(reads, fleet.manager_address, "matureKeys()", [], {:uint, 256}),
         {:ok, preview} <- Reads.each(assets, &preview(reads, fleet, &1, bps, keys)) do
      opens_at = if next_run_at > 0, do: DateTime.from_unix!(next_run_at)

      blocked =
        cond do
          opens_at == nil -> %{"run_split" => :no_keys_sold}
          DateTime.before?(Reads.now(reads), opens_at) -> %{"run_split" => {:opens_at, opens_at}}
          true -> %{}
        end

      {:ok, [Review.step("run_split", treasury, Call.encode("runDailySplit()", []))],
       %{
         assets: named(fleet, preview),
         rate_bps: bps,
         keys: keys,
         last_run_at: if(last_run_at > 0, do: DateTime.from_unix!(last_run_at)),
         opens_at: opens_at,
         blocked: blocked
       }}
    else
      # No preview: the page says the network can't be reached.
      _unread -> {:problem, :unread, %{blocked: %{}}}
    end
  end

  # Part or all of one advance, back to the treasury from whoever presses.
  # ETH goes with the call; a token is approved to the treasury first, as a
  # step of its own.
  def steps(:return_advance, %{fleet: fleet, signer: signer, advance_id: id, inputs: inputs}) do
    figures = %{advance_id: id}

    with {:ok, reads} <- reads(figures),
         {:ok, [operator, asset, outstanding, _purpose]} <- advance(reads, fleet, id, figures),
         asset = advanced_asset(fleet, asset),
         figures =
           Map.merge(figures, %{operator: operator, asset: asset, outstanding: outstanding}),
         {:ok, decimals} <- decimals(asset, figures),
         {:ok, amount} <-
           Build.typed(
             inputs,
             "amount",
             &Typed.amount(&1, decimals, Typed.largest_uint256()),
             figures
           ),
         figures = Map.put(figures, :amount, amount),
         {:ok, held, allowance} <- standing(reads, fleet, signer, asset, figures) do
      native? = asset.address == Treasury.native()

      give_back =
        Review.step(
          "return",
          fleet.treasury_address,
          Call.encode("returnAdvance(uint256,uint256)", [id, amount]),
          if(native?, do: amount, else: 0)
        )

      {:ok, if(native?, do: [give_back], else: [approve(fleet, asset, amount), give_back]),
       Map.put(figures, :blocked, return_blocked(outstanding, amount, held, allowance))}
    end
  end

  # The protocol share the fleet owes REGENT staking, which anyone may send.
  def steps(:send_share, %{fleet: fleet}) do
    figures = %{owed: nil}

    with {:ok, reads} <- Reads.at_head(),
         {:ok, owed} <-
           Reads.one(reads, fleet.manager_address, "protocolShareOwed()", [], {:uint, 256}) do
      {:ok,
       [
         Review.step("send_share", fleet.manager_address, Call.encode("sendProtocolShare()", []))
       ], %{owed: owed, blocked: if(owed == 0, do: %{"send_share" => :nothing_owed}, else: %{})}}
    else
      _unread -> {:problem, :unread, figures}
    end
  end

  # The USDC from Key sales the fleet's manager holds until the REGENT buyer
  # turns it into REGENT for the treasury. The buyer serves every fleet in
  # turn, one piece at a time, so a press converts the next piece in line,
  # which may be another fleet's: at most the USDC typed, and at most 250
  # USDC, as the buyer limits it.
  def steps(:convert, %{fleet: fleet, inputs: inputs}) do
    manager = fleet.manager_address

    with {:ok, reads} <- Reads.at_head(),
         {:ok, waiting} <- Reads.one(reads, manager, "pendingConversion()", [], {:uint, 256}),
         {:ok, buyer} <- Reads.one(reads, manager, "REGENT_BUYER()", [], :address),
         {:ok, in_line} <- Reads.one(reads, buyer, "queueLength()", [], {:uint, 256}),
         {:ok, next_piece_at} <- Reads.one(reads, buyer, "nextPieceAt()", [], {:uint, 64}),
         opens_at = if(next_piece_at > 0, do: DateTime.from_unix!(next_piece_at)),
         figures = %{
           waiting: waiting,
           in_line: in_line,
           opens_at: opens_at,
           blocked: convert_blocked(reads, in_line, opens_at)
         },
         {:ok, amount} <-
           Build.typed(
             inputs,
             "amount",
             &Typed.amount(&1, @usdc_decimals, Typed.largest_uint256()),
             figures
           ),
         {:ok, blocked} <- convert_too_big(reads, buyer, amount, figures.blocked) do
      {:ok, [Review.step("convert", buyer, Call.encode("convert(uint256)", [amount]))],
       figures |> Map.put(:amount, amount) |> Map.put(:blocked, blocked)}
    else
      {:problem, problem, figures} -> {:problem, problem, figures}
      _unread -> {:problem, :unread, %{blocked: %{}}}
    end
  end

  # An empty line, or a piece not open yet, is sure to fail.
  defp convert_blocked(_reads, 0, _opens_at), do: %{"convert" => :nothing_queued}

  defp convert_blocked(reads, _in_line, opens_at) do
    if opens_at && DateTime.before?(Reads.now(reads), opens_at),
      do: %{"convert" => {:opens_at, opens_at}},
      else: %{}
  end

  # Otherwise the piece itself is tried at the head block: the buyer refuses one
  # that moves the route's price by more than 1%, so a piece too big for the
  # pools right now is sure to fail. A smaller one may not be, and the reason
  # names the most whole USDC the buyer takes now, or nil when it takes none.
  defp convert_too_big(_reads, _buyer, _amount, blocked) when blocked != %{}, do: {:ok, blocked}

  defp convert_too_big(reads, buyer, amount, blocked) do
    case piece_goes_through?(reads, buyer, amount) do
      {:ok, true} ->
        {:ok, blocked}

      {:ok, false} ->
        top = min(div(amount - 1, @usdc_unit), div(@piece_usdc, @usdc_unit))

        with {:ok, largest} <- largest_piece(reads, buyer, 1, top, nil),
             do: {:ok, %{"convert" => {:too_big, largest}}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # The most whole USDC from `low` to `high` the buyer takes now, by halving:
  # a piece goes through or not by its size alone.
  defp largest_piece(_reads, _buyer, low, high, found) when low > high, do: {:ok, found}

  defp largest_piece(reads, buyer, low, high, found) do
    middle = div(low + high, 2)

    case piece_goes_through?(reads, buyer, middle * @usdc_unit) do
      {:ok, true} -> largest_piece(reads, buyer, middle + 1, high, middle * @usdc_unit)
      {:ok, false} -> largest_piece(reads, buyer, low, middle - 1, found)
      {:error, reason} -> {:error, reason}
    end
  end

  defp piece_goes_through?(reads, buyer, amount),
    do: Reads.goes_through?(reads, buyer, "convert(uint256)", [amount])

  defp approve(fleet, asset, amount),
    do:
      Review.step(
        "approve",
        asset.address,
        Call.encode("approve(address,uint256)", [fleet.treasury_address, amount])
      )

  # Why returning `amount` is certain to fail now, if it is. ETH goes with
  # the call, so its allowance is never needed and reads as all of it.
  defp return_blocked(outstanding, amount, held, allowance) do
    cond do
      outstanding == 0 -> %{"return" => :advance_returned}
      amount > outstanding -> %{"return" => :above_outstanding}
      held < amount -> %{"return" => :not_enough}
      allowance < amount -> %{"return" => :approve_first}
      true -> %{}
    end
  end

  # One asset as the treasury would split it now: its balance, the least it
  # splits from (0.05 ETH, or 100 of a token), and each key's part, nothing
  # under the least.
  defp preview(reads, fleet, asset, bps, keys) do
    with {:ok, balance} <- held(reads, asset, fleet.treasury_address),
         {:ok, threshold} <- threshold(reads, asset) do
      per_key =
        if keys == 0 or balance < threshold, do: 0, else: div(div(balance * bps, 10_000), keys)

      {:ok, %{asset: asset, balance: balance, threshold: threshold, per_key: per_key}}
    end
  end

  defp threshold(reads, asset) do
    if asset == Treasury.native() do
      {:ok, @eth_threshold}
    else
      with {:ok, decimals} <- Reads.one(reads, asset, "decimals()", [], {:uint, 8}),
           do: {:ok, 100 * 10 ** decimals}
    end
  end

  defp held(reads, asset, account) do
    if asset == Treasury.native(),
      do: Reads.balance(reads, account),
      else: Reads.one(reads, asset, "balanceOf(address)", [account], {:uint, 256})
  end

  defp reads(figures) do
    case Reads.at_head() do
      {:ok, reads} -> {:ok, reads}
      {:error, _reason} -> {:problem, :unread, figures}
    end
  end

  # An advance the treasury never made has no operator.
  defp advance(reads, fleet, id, figures) do
    types = [:address, :address, {:uint, 256}, :bytes32]

    case Reads.many(reads, fleet.treasury_address, "advances(uint256)", [id], types) do
      {:ok, [operator | _rest] = advance} ->
        if operator == Treasury.native(),
          do: {:problem, :advance_unknown, figures},
          else: {:ok, advance}

      {:error, _reason} ->
        {:problem, :unread, figures}
    end
  end

  # What the signer holds of the asset, and has let the treasury take of it.
  defp standing(reads, fleet, signer, asset, figures) do
    with {:ok, held} <- held(reads, asset.address, signer),
         {:ok, allowance} <- allowance(reads, fleet, signer, asset.address) do
      {:ok, held, allowance}
    else
      _unread -> {:problem, :unread, figures}
    end
  end

  defp allowance(reads, fleet, signer, asset) do
    if asset == Treasury.native(),
      do: {:ok, Typed.largest_uint256()},
      else:
        Reads.one(
          reads,
          asset,
          "allowance(address,address)",
          [signer, fleet.treasury_address],
          {:uint, 256}
        )
  end

  # The advance's asset, with the symbol and decimals it reported, as the
  # treasury page types a return of all of it: any token the fleet recorded,
  # held now or not.
  defp advanced_asset(fleet, asset) do
    {symbol, decimals} = Map.get(Treasury.assets(fleet).details, asset, {nil, nil})
    %{address: asset, symbol: symbol, decimals: decimals}
  end

  # An amount of a token that never said its decimals can't be read.
  defp decimals(%{decimals: nil}, figures), do: {:problem, :decimals_unknown, figures}
  defp decimals(%{decimals: decimals}, _figures), do: {:ok, decimals}

  defp named(fleet, preview), do: Enum.map(preview, &Map.merge(named_asset(fleet, &1.asset), &1))

  defp named_asset(fleet, asset) do
    Enum.find(
      Treasury.payable_assets(fleet),
      %{address: asset, symbol: nil, decimals: nil, usdc?: false, known?: false},
      &(&1.address == asset)
    )
  end
end
