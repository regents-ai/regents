defmodule AshPlatform.Autolaunch.BidActions do
  @moduledoc false

  alias AshPlatform.{Accounts, Autolaunch}
  alias AshPlatform.Actors.Human
  alias AshPlatform.Autolaunch.ChainClient
  alias AshPlatform.WalletActions.{Abi, AuctionAbi, Envelope}

  @auction_resource "autolaunch_auction"
  @bid_resource "autolaunch_bid"
  @contract_name "IContinuousClearingAuction"
  @q96 79_228_162_514_264_337_593_543_950_336
  @uint128_max Integer.pow(2, 128) - 1
  @uint256_max Integer.pow(2, 256) - 1
  @auction_actions ~w(submit_bid)
  @bid_actions ~w(exit_bid return_quote_token claim_bid)
  @risk %{
    "submit_bid" =>
      "Approve the exact quote-token amount, then submit this bid from your connected wallet.",
    "exit_bid" => "Exit this bid and return its available quote tokens to the bid owner.",
    "return_quote_token" => "Return the available quote tokens from this failed auction bid.",
    "claim_bid" => "Claim the launch tokens purchased by this bid to the bid owner."
  }

  def quote(auction_id, amount, max_price, opts) do
    with {:ok, auction} <- auction(auction_id, opts),
         {:ok, amount} <- positive_decimal(amount),
         {:ok, max_price} <- positive_decimal(max_price) do
      current_price = nonnegative_decimal_or_zero(auction.current_clearing_price)
      projected_price = if Decimal.gt?(current_price, 0), do: current_price, else: max_price
      active? = Decimal.compare(max_price, current_price) != :lt

      estimated_tokens =
        if active? and Decimal.gt?(projected_price, 0),
          do: Decimal.div(amount, projected_price),
          else: Decimal.new(0)

      {:ok,
       %{
         auction_id: auction.id,
         amount: decimal_string(amount),
         max_price: decimal_string(max_price),
         quote_token: %{
           address: auction.quote_token_address,
           symbol: auction.quote_token_symbol,
           decimals: auction.quote_token_decimals
         },
         current_clearing_price: decimal_string(current_price),
         projected_clearing_price: decimal_string(projected_price),
         would_be_active_now: active?,
         status_band: status_band(active?, max_price, projected_price),
         estimated_tokens_if_end_now: decimal_string(estimated_tokens),
         warnings: quote_warnings(auction, active?)
       }}
    end
  end

  def prepare_bid(auction_id, signer, amount, max_price, opts) do
    actor = Keyword.get(opts, :actor)

    with %Human{} <- actor,
         {:ok, signer} <- normalize_address(signer),
         :ok <- verified_wallet(actor, signer),
         {:ok, auction} <- auction(auction_id, opts),
         {:ok, auction_address} <- normalize_address(auction.auction_address),
         {:ok, quote_token} <- normalize_address(auction.quote_token_address),
         {:ok, decimals} <- token_decimals(auction.quote_token_decimals),
         {:ok, amount_decimal} <- positive_decimal(amount),
         {:ok, max_price_decimal} <- positive_decimal(max_price),
         {:ok, amount_raw} <- token_units(amount_decimal, decimals),
         {:ok, max_price_q96} <- price_q96(max_price_decimal),
         {:ok, data} <-
           encode(fn ->
             AuctionAbi.encode_submit_bid(max_price_q96, amount_raw, signer)
           end),
         {:ok, approval_data} <-
           encode(fn -> AuctionAbi.encode_approval(auction_address, amount_raw) end) do
      approval = %{
        token: quote_token,
        spender: auction_address,
        amount: Integer.to_string(amount_raw),
        data: approval_data,
        mode: "exact"
      }

      {:ok,
       Envelope.new("submit_bid", signer, data,
         to: auction_address,
         resource: @auction_resource,
         contract_name: @contract_name,
         risk_copy: @risk["submit_bid"],
         approval: approval,
         arguments: %{
           auction_id: auction.id,
           amount: decimal_string(amount_decimal),
           amount_atomic: Integer.to_string(amount_raw),
           max_price: decimal_string(max_price_decimal),
           max_price_q96: Integer.to_string(max_price_q96),
           quote_token: quote_token,
           quote_token_decimals: decimals,
           recipient: signer
         }
       )}
    else
      nil -> {:error, :authentication_required}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :authentication_required}
    end
  end

  def prepare_position(action, bid_id, opts) when action in @bid_actions do
    actor = Keyword.get(opts, :actor)

    with %Human{} <- actor,
         {:ok, bid} <- owned_bid(bid_id, actor),
         :ok <- action_available(action, bid.status),
         {:ok, auction_address} <- normalize_address(bid.auction_address),
         {:ok, onchain_bid_id} <- onchain_bid_id(bid.onchain_bid_id),
         {:ok, data} <- encode(fn -> AuctionAbi.encode_position(action, onchain_bid_id) end) do
      {:ok,
       Envelope.new(action, bid.owner_address, data,
         to: auction_address,
         resource: @bid_resource,
         contract_name: @contract_name,
         risk_copy: Map.fetch!(@risk, action),
         arguments: %{
           bid_id: bid.bid_id,
           auction_id: bid.auction_id,
           onchain_bid_id: Integer.to_string(onchain_bid_id),
           recipient: bid.owner_address
         }
       )}
    else
      nil -> {:error, :authentication_required}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :authentication_required}
    end
  end

  def confirm(envelope, transaction_hash, approval_transaction_hash, opts) do
    actor = Keyword.get(opts, :actor)
    envelope = atomize_envelope(envelope)

    with %Human{} <- actor,
         {:ok, stored} <- stored_identity(envelope, actor),
         true <- valid_for_confirmation?(envelope, stored),
         :ok <- verified_wallet(actor, envelope.expected_signer) do
      case ChainClient.module().confirm(
             envelope,
             transaction_hash,
             approval_transaction_hash
           ) do
        {:ok, result} ->
          {:ok, Map.put(result, stored_key(envelope.resource), stored)}

        {:error, :transaction_reverted} ->
          {:ok,
           %{
             transaction_hash: String.downcase(transaction_hash),
             receipt_verified: true,
             transaction_reverted: true
           }}

        {:error, reason} ->
          {:error, reason}
      end
    else
      false -> {:error, :stale_or_invalid_action}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :authentication_required}
    end
  end

  def restore(envelope, opts) do
    actor = Keyword.get(opts, :actor)
    envelope = atomize_envelope(envelope)

    with %Human{} <- actor,
         {:ok, stored} <- stored_identity(envelope, actor),
         true <- valid_for_confirmation?(envelope, stored),
         :ok <- verified_wallet(actor, envelope.expected_signer) do
      {:ok, envelope}
    else
      _ -> {:error, :invalid_submitted_action}
    end
  end

  def approval_status(envelope, transaction_hash, opts) do
    actor = Keyword.get(opts, :actor)
    envelope = atomize_envelope(envelope)

    with %Human{} <- actor,
         {:ok, stored} <- stored_identity(envelope, actor),
         true <- valid_for_confirmation?(envelope, stored),
         :ok <- verified_wallet(actor, envelope.expected_signer) do
      ChainClient.module().approval_status(envelope, transaction_hash)
    else
      _ -> {:error, :invalid_submitted_action}
    end
  end

  defp auction(auction_id, _opts) do
    case Autolaunch.get_public_auction(auction_id, actor: nil) do
      {:ok, nil} -> {:error, :auction_not_found}
      result -> result
    end
  end

  defp owned_bid(bid_id, actor) do
    case Autolaunch.get_my_bid_position(bid_id, actor: actor) do
      {:ok, nil} -> {:error, :bid_not_found}
      result -> result
    end
  end

  defp stored_identity(%{resource: @auction_resource} = envelope, _actor) do
    with auction_id when is_binary(auction_id) <- argument(envelope, :auction_id),
         {:ok, auction} <- auction(auction_id, []) do
      {:ok, auction}
    else
      _ -> {:error, :invalid_auction_identity}
    end
  end

  defp stored_identity(%{resource: @bid_resource} = envelope, actor) do
    with bid_id when is_binary(bid_id) <- argument(envelope, :bid_id),
         {:ok, bid} <- owned_bid(bid_id, actor) do
      {:ok, bid}
    else
      _ -> {:error, :invalid_bid_identity}
    end
  end

  defp stored_identity(_envelope, _actor), do: {:error, :invalid_resource}

  defp valid_for_confirmation?(%{resource: @auction_resource} = envelope, auction) do
    case normalize_address(auction.auction_address) do
      {:ok, to} ->
        Envelope.valid_for_confirmation?(envelope,
          resource: @auction_resource,
          to: to,
          signer: envelope.expected_signer,
          contract_name: @contract_name,
          actions: @auction_actions
        )

      _ ->
        false
    end
  end

  defp valid_for_confirmation?(%{resource: @bid_resource} = envelope, bid) do
    with {:ok, to} <- normalize_address(bid.auction_address),
         {:ok, owner} <- normalize_address(bid.owner_address),
         true <- owner == envelope.expected_signer,
         true <- argument(envelope, :onchain_bid_id) == bid.onchain_bid_id do
      Envelope.valid_for_confirmation?(envelope,
        resource: @bid_resource,
        to: to,
        signer: owner,
        contract_name: @contract_name,
        actions: @bid_actions
      )
    else
      _ -> false
    end
  end

  defp action_available("return_quote_token", "returnable"), do: :ok
  defp action_available("exit_bid", status) when status in ~w(active borderline inactive), do: :ok
  defp action_available("claim_bid", "claimable"), do: :ok
  defp action_available(_action, _status), do: {:error, :bid_action_unavailable}

  defp positive_decimal(value) when is_binary(value) do
    value = String.trim(value)

    with true <- byte_size(value) <= 100,
         true <- String.match?(value, ~r/^\d+(?:\.\d+)?$/),
         {decimal, ""} <- Decimal.parse(value),
         :gt <- Decimal.compare(decimal, 0) do
      {:ok, decimal}
    else
      _ -> {:error, :invalid_decimal}
    end
  end

  defp positive_decimal(_value), do: {:error, :invalid_decimal}

  defp nonnegative_decimal_or_zero(value) when is_binary(value) do
    case Decimal.parse(String.trim(value)) do
      {decimal, ""} ->
        if Decimal.compare(decimal, 0) in [:eq, :gt], do: decimal, else: Decimal.new(0)

      _ ->
        Decimal.new(0)
    end
  end

  defp nonnegative_decimal_or_zero(_value), do: Decimal.new(0)

  defp token_units(decimal, decimals) do
    scale = Integer.pow(10, decimals)
    scaled = Decimal.mult(decimal, scale)
    rounded = Decimal.round(scaled, 0)

    if Decimal.equal?(scaled, rounded) do
      amount = Decimal.to_integer(rounded)
      if amount in 1..@uint128_max, do: {:ok, amount}, else: {:error, :invalid_amount}
    else
      {:error, :invalid_amount_precision}
    end
  end

  defp price_q96(decimal) do
    text = Decimal.to_string(decimal, :normal)
    [whole, fraction] = String.split(text <> ".", ".", parts: 2)
    fraction = String.trim_trailing(fraction, ".")
    numerator = String.to_integer(whole <> fraction)
    denominator = Integer.pow(10, String.length(fraction))
    scaled = numerator * @q96
    quotient = div(scaled, denominator)
    rounded = if rem(scaled, denominator) * 2 >= denominator, do: quotient + 1, else: quotient

    if rounded in 1..@uint256_max, do: {:ok, rounded}, else: {:error, :invalid_price}
  rescue
    _ -> {:error, :invalid_price}
  end

  defp token_decimals(value) when is_integer(value) and value in 0..36, do: {:ok, value}
  defp token_decimals(_value), do: {:error, :invalid_quote_token}

  defp onchain_bid_id(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} when integer in 0..@uint256_max -> {:ok, integer}
      _ -> {:error, :invalid_onchain_bid_id}
    end
  end

  defp onchain_bid_id(_value), do: {:error, :invalid_onchain_bid_id}

  defp normalize_address(value) do
    {:ok, Abi.normalize_address!(value)}
  rescue
    _ -> {:error, :invalid_address}
  end

  defp verified_wallet(%Human{} = actor, signer) do
    with {:ok, account} <- Accounts.get_human_account(actor.human_account_id, actor: actor),
         wallets when is_list(wallets) <- account.wallet_addresses,
         true <- Enum.any?(wallets, &(normalize_or_nil(&1) == signer)) do
      :ok
    else
      _ -> {:error, :wrong_signer}
    end
  end

  defp normalize_or_nil(value) do
    Abi.normalize_address!(value)
  rescue
    _ -> nil
  end

  defp encode(fun) do
    {:ok, fun.()}
  rescue
    _ -> {:error, :invalid_calldata}
  end

  defp status_band(false, _max_price, _projected_price), do: "inactive"

  defp status_band(true, max_price, projected_price) do
    if Decimal.equal?(max_price, projected_price), do: "borderline", else: "active"
  end

  defp quote_warnings(auction, active?) do
    []
    |> maybe_warning(not active?, "max_price_below_current_clearing_price")
    |> maybe_warning(auction.state != :active, "auction_not_biddable")
  end

  defp maybe_warning(warnings, true, warning), do: [warning | warnings]
  defp maybe_warning(warnings, false, _warning), do: warnings
  defp decimal_string(decimal), do: decimal |> Decimal.normalize() |> Decimal.to_string(:normal)
  defp stored_key(@auction_resource), do: :auction
  defp stored_key(@bid_resource), do: :bid

  defp argument(envelope, key) do
    envelope
    |> Map.get(:arguments, %{})
    |> field(key)
  end

  defp atomize_envelope(envelope) when is_map(envelope) do
    %{
      action_id: field(envelope, :action_id),
      idempotency_key: field(envelope, :idempotency_key),
      resource: field(envelope, :resource),
      action: field(envelope, :action),
      chain_id: field(envelope, :chain_id),
      to: field(envelope, :to),
      value: field(envelope, :value),
      data: field(envelope, :data),
      expected_signer: field(envelope, :expected_signer),
      prepared_at: field(envelope, :prepared_at),
      expires_at: field(envelope, :expires_at),
      risk_copy: field(envelope, :risk_copy),
      approval: field(envelope, :approval),
      arguments: field(envelope, :arguments),
      metadata: field(envelope, :metadata),
      confirmation_token: field(envelope, :confirmation_token)
    }
  end

  defp atomize_envelope(_envelope), do: %{}
  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
