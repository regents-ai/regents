defmodule Regents.Keyfleet.Chain.MoneyLog do
  @moduledoc """
  Reads the money logs of a fleet's contracts into the fields of a
  `Regents.Keyfleet.Treasury.Event`, each as `{:treasury_event, fields}` with a
  `kind`. Amounts are in the asset's own units, any uint256; ETH is the
  zero address.

  From the fleet contract (`fleet_topics/0`): `ForwardedToTreasury`, an
  asset sent to the fleet by mistake forwarded to its treasury
  (`:forwarded`), and `ProtocolShareSent`, the protocol share deposited in
  REGENT staking (`:protocol_share_sent`).

  From its treasury (`treasury_topics/0`): a proposal's payment (`:paid`),
  advance (`:advanced`), each a share of the treasury's balance of the asset
  in parts per million and the amount it came to, and an advance coming back
  (`:advance_returned`);
  each daily split run (`:daily_split_run`) and what it did with each bound
  asset (`:split_allocated`, `:split_skipped`, `:split_transfer_failed`); a
  new split rate (`:daily_split_rate_set`); OUSD admitted
  (`:ousd_admitted`); the fleet's launch token bound (`:launch_token_bound`);
  and the treasury's own Lit wallet request approved or revoked
  (`:signature_approved`, `:signature_revoked`), by the digest Lit checks.

  From its reward ledger (`rewards_topics/0`): a key's rewards settled to its
  holder (`:settled`) and credit paid out (`:claimed`).

  From the REGENT buyer every fleet shares (`buyer_topics/0`): a piece of the
  fleet's USDC from Key sales turned into REGENT for its treasury
  (`:regent_bought`), the USDC it took, the WETH it went through and the
  REGENT the treasury got (`decode_bought/4`).
  """

  alias RegentChain.Abi
  alias RegentChain.Event

  @fields [
    :asset,
    :account,
    :by,
    :share,
    :amount,
    :balance,
    :per_key,
    :keys,
    :bps,
    :voted,
    :advance_id,
    :purpose_hash,
    :outstanding,
    :threshold,
    :launch_id,
    :token_id,
    :signed_hash,
    :usdc_in,
    :weth_mid,
    :regent_out
  ]

  # The buyer's fields that name the fleet a piece was for, which pick the
  # fleet and are not kept.
  @fleet_named [:payer, :recipient]

  # Each event: its kind, its indexed fields after topic0 and its data
  # fields, as `{field, type}`.
  @events %{
    fleet: %{
      "ForwardedToTreasury(address,address,uint256)" =>
        {:forwarded, [asset: :address, by: :address], [amount: {:uint, 256}]},
      "ProtocolShareSent(address,uint256)" =>
        {:protocol_share_sent, [by: :address], [amount: {:uint, 256}]}
    },
    treasury: %{
      "Paid(address,address,uint32,uint256)" =>
        {:paid, [asset: :address, account: :address], [share: {:uint, 32}, amount: {:uint, 256}]},
      "Advanced(uint256,address,address,uint32,uint256,bytes32)" =>
        {:advanced, [advance_id: {:uint, 256}, account: :address, asset: :address],
         [share: {:uint, 32}, amount: {:uint, 256}, purpose_hash: :bytes32]},
      "AdvanceReturned(uint256,address,uint256,uint256)" =>
        {:advance_returned, [advance_id: {:uint, 256}, by: :address],
         [amount: {:uint, 256}, outstanding: {:uint, 256}]},
      "DailySplitRun(bool,uint256,uint256)" =>
        {:daily_split_run, [voted: :bool], [keys: {:uint, 256}, bps: {:uint, 256}]},
      "SplitAllocated(address,uint256,uint256,uint256)" =>
        {:split_allocated, [asset: :address],
         [balance: {:uint, 256}, per_key: {:uint, 256}, keys: {:uint, 256}]},
      "SplitSkipped(address,uint256)" =>
        {:split_skipped, [asset: :address], [balance: {:uint, 256}]},
      "SplitTransferFailed(address,uint256)" =>
        {:split_transfer_failed, [asset: :address], [amount: {:uint, 256}]},
      "DailySplitRateSet(uint256)" => {:daily_split_rate_set, [], [bps: {:uint, 256}]},
      "OusdAdmitted(address,uint256)" =>
        {:ousd_admitted, [asset: :address], [threshold: {:uint, 256}]},
      "LaunchTokenBound(uint256,address,uint256)" =>
        {:launch_token_bound, [launch_id: {:uint, 256}, asset: :address],
         [threshold: {:uint, 256}]},
      "LitCreateWalletApproved(bytes32)" => {:signature_approved, [signed_hash: :bytes32], []},
      "LitCreateWalletRevoked(bytes32)" => {:signature_revoked, [signed_hash: :bytes32], []}
    },
    rewards: %{
      "Settled(uint256,address,address,uint256)" =>
        {:settled, [token_id: {:uint, 63}, asset: :address, account: :address],
         [amount: {:uint, 256}]},
      "Claimed(address,address,address,uint256)" =>
        {:claimed, [asset: :address, account: :address, by: :address], [amount: {:uint, 256}]}
    },
    buyer: %{
      "RegentBought(address,address,uint256,uint256,uint256)" =>
        {:regent_bought, [payer: :address, recipient: :address],
         [usdc_in: {:uint, 256}, weth_mid: {:uint, 256}, regent_out: {:uint, 256}]}
    }
  }

  @by_topic Map.new(@events, fn {contract, events} ->
              {contract,
               Map.new(events, fn {signature, event} -> {Event.topic0(signature), event} end)}
            end)

  @doc "Every kind of record read here."
  def kinds, do: for({_contract, events} <- @events, {_sig, {kind, _, _}} <- events, do: kind)

  @doc "The fields each kind of record carries, beside its place on the chain."
  def fields_of_kinds,
    do:
      for(
        {_contract, events} <- @events,
        {_sig, {kind, indexed, data}} <- events,
        into: %{},
        do: {kind, Keyword.keys(indexed ++ data) -- @fleet_named}
      )

  @doc "Every field any kind of record carries."
  def fields, do: @fields

  @contracts for {contract, events} <- @events,
                 {_sig, {kind, _indexed, _data}} <- events,
                 into: %{},
                 do: {kind, contract}

  @doc "The contract a kind of record is read from: `:fleet`, `:treasury`, `:rewards` or `:buyer`."
  def contract(kind), do: Map.fetch!(@contracts, kind)

  @doc "The topic0 of each event read from the fleet contract."
  def fleet_topics, do: Map.keys(@by_topic.fleet)

  @doc "The topic0 of each event read from the treasury."
  def treasury_topics, do: Map.keys(@by_topic.treasury)

  @doc "The topic0 of each event read from the reward ledger."
  def rewards_topics, do: Map.keys(@by_topic.rewards)

  @doc "The topic0 of each event read from the REGENT buyer."
  def buyer_topics, do: Map.keys(@by_topic.buyer)

  @doc """
  A log of the REGENT buyer, its indexed topics after topic0, as 32-byte
  words, and its data, as one record of `fleet`: a piece its manager paid for,
  with its treasury getting the REGENT. `:other_fleet` for another fleet's
  piece, and `:error` for any other log, a malformed one, or a piece of this
  fleet's manager whose REGENT went anywhere but its treasury.
  """
  def decode_bought(fleet, topic0, topics, data) do
    with {:ok, {:treasury_event, fields}} <- read_log(:buyer, topic0, topics, data) do
      %{manager_address: manager, treasury_address: treasury} = fleet

      case Map.split(fields, @fleet_named) do
        {%{payer: ^manager, recipient: ^treasury}, fields} -> {:ok, {:treasury_event, fields}}
        {%{payer: ^manager}, _fields} -> :error
        {_another_fleet, _fields} -> :other_fleet
      end
    end
  end

  @doc """
  A log of `contract` (`:fleet`, `:treasury` or `:rewards`), its indexed
  topics after topic0, as 32-byte words, and its data, as one record;
  `:error` for any other log or a malformed one.
  """
  def decode(contract, topic0, topics, data) when contract in [:fleet, :treasury, :rewards],
    do: read_log(contract, topic0, topics, data)

  defp read_log(contract, topic0, topics, data) do
    with {:ok, {kind, indexed, data_fields}} <- Map.fetch(@by_topic[contract], topic0),
         true <- length(topics) == length(indexed),
         {:ok, from_topics} <- words(topics, Keyword.values(indexed)),
         {:ok, from_data} <- Abi.decode(data, Keyword.values(data_fields)) do
      values =
        Enum.zip(Keyword.keys(indexed) ++ Keyword.keys(data_fields), from_topics ++ from_data)

      {:ok,
       {:treasury_event,
        @fields
        |> Map.new(&{&1, nil})
        |> Map.merge(Map.new(values, &stored/1))
        |> Map.put(:kind, kind)}}
    else
      _malformed -> :error
    end
  end

  defp words(topics, types) do
    Enum.zip(topics, types)
    |> Enum.reduce_while({:ok, []}, fn {topic, type}, {:ok, values} ->
      case Abi.word(topic, type) do
        {:ok, value} -> {:cont, {:ok, [value | values]}}
        :error -> {:halt, :error}
      end
    end)
    |> then(fn
      {:ok, values} -> {:ok, Enum.reverse(values)}
      :error -> :error
    end)
  end

  # Amounts and counts are kept as decimals, which hold any uint256; a key
  # number fits a bigint.
  defp stored({field, value}) when is_integer(value) and field != :token_id,
    do: {field, Decimal.new(value)}

  defp stored(pair), do: pair
end
