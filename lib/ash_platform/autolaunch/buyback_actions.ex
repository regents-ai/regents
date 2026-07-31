defmodule AshPlatform.Autolaunch.BuybackActions do
  @moduledoc false

  require Logger

  alias AshPlatform.{Accounts, Autolaunch}
  alias AshPlatform.Actors.Human
  alias AshPlatform.Autolaunch.{BuybackChainClient, ReferencePriceClient}
  alias AshPlatform.WalletActions.{Abi, BuybackAbi, Envelope}

  @resource "autolaunch_buyback"
  @action "settle_treasury_buyback"
  @contract_name "RegentStakingRevenueRouter"
  @base_chain_id 8453
  @accepted_twap_sources ~w(twap pool_twap uniswap_twap)
  @twap_max_age_microseconds 900_000_000
  @maximum_price_deviation_bps 1_000
  @uint256_max Integer.pow(2, 256) - 1
  @risk_copy "Settle this pending USDC buyback through the subject revenue router."

  def prepare(subject_id, signer, amount_usdc, minimum_regent_output, opts) do
    actor = Keyword.get(opts, :actor)

    with %Human{} <- actor,
         {:ok, signer} <- normalize_address(signer),
         :ok <- verified_wallet(actor, signer),
         {:ok, subject} <- subject(subject_id),
         :ok <- base_chain(subject.chain_id),
         {:ok, router} <- normalize_address(subject.revenue_router_address),
         {:ok, treasury} <- normalize_address(subject.treasury_address),
         {:ok, subject_bytes32} <- bytes32(subject.subject_id),
         {:ok, amount_decimal, amount_raw} <- decimal_units(amount_usdc, 6),
         {:ok, output_decimal, minimum_output_raw} <-
           decimal_units(minimum_regent_output, 18),
         :ok <- market_guards(subject, amount_raw, minimum_output_raw),
         {:ok, data} <-
           encode(fn ->
             BuybackAbi.encode_settlement(
               subject_bytes32,
               treasury,
               amount_raw,
               minimum_output_raw,
               subject_bytes32
             )
           end) do
      {:ok,
       Envelope.new(@action, signer, data,
         to: router,
         resource: @resource,
         contract_name: @contract_name,
         risk_copy: @risk_copy,
         arguments: %{
           subject_id: subject.subject_id,
           revenue_router: router,
           treasury: treasury,
           amount_usdc: decimal_string(amount_decimal),
           amount_usdc_atomic: Integer.to_string(amount_raw),
           minimum_regent_output: decimal_string(output_decimal),
           minimum_regent_output_atomic: Integer.to_string(minimum_output_raw),
           source_ref: subject_bytes32
         }
       )}
    else
      nil -> {:error, :authentication_required}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :authentication_required}
    end
  end

  def confirm(envelope, transaction_hash, opts) do
    actor = Keyword.get(opts, :actor)
    envelope = atomize_envelope(envelope)

    with %Human{} <- actor,
         {:ok, stored} <- stored_identity(envelope),
         true <- valid_for_confirmation?(envelope, stored),
         :ok <- verified_wallet(actor, envelope.expected_signer) do
      case BuybackChainClient.module().confirm(envelope, transaction_hash) do
        {:ok, result} ->
          attach_refreshed_subject(result, stored.subject_id)

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
         {:ok, stored} <- stored_identity(envelope),
         true <- valid_for_confirmation?(envelope, stored),
         :ok <- verified_wallet(actor, envelope.expected_signer) do
      {:ok, envelope}
    else
      _ -> {:error, :invalid_submitted_action}
    end
  end

  defp market_guards(subject, amount_raw, minimum_output_raw) do
    result =
      with :ok <- pending_guard(subject.pending_buyback_usdc_raw, amount_raw),
           {:ok, twap} <- twap_guard(subject.subject_id),
           {:ok, reference} <- reference_guard(),
           :ok <- price_band_guard(twap, reference) do
        minimum_output_guard(amount_raw, minimum_output_raw, reference)
      end

    case result do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "autolaunch buyback market paused #{inspect(%{subject_id: subject.subject_id, reason: reason})}"
        )

        {:error, :buyback_market_paused}
    end
  end

  defp pending_guard(pending_raw, amount_raw) do
    case nonnegative_integer(pending_raw) do
      {:ok, pending} when pending > 0 and amount_raw <= pending -> :ok
      {:ok, pending} when pending > 0 -> {:error, :amount_exceeds_pending_balance}
      _ -> {:error, :pending_balance_unavailable}
    end
  end

  defp twap_guard(subject_id) do
    case Autolaunch.get_latest_subject_token_price(subject_id, actor: nil) do
      {:ok,
       %{
         price_source: source,
         price_updated_at: %DateTime{} = observed_at,
         price_quote: price
       }}
      when source in @accepted_twap_sources ->
        with age when age in 0..@twap_max_age_microseconds <-
               DateTime.diff(Envelope.current_time(), observed_at, :microsecond),
             {:ok, parsed} <- positive_decimal(price) do
          {:ok, parsed}
        else
          age when is_integer(age) -> {:error, {:twap_age_out_of_range, age}}
          {:error, _reason} -> {:error, :twap_price_invalid}
        end

      {:ok, %{price_source: source, price_updated_at: nil}}
      when source in @accepted_twap_sources ->
        {:error, :twap_timestamp_missing}

      {:ok, %{price_source: source}} ->
        {:error, {:twap_source_not_allowed, source}}

      {:ok, nil} ->
        {:error, :twap_missing}

      {:error, _reason} ->
        {:error, :twap_read_failed}
    end
  end

  defp reference_guard do
    case ReferencePriceClient.fetch_regent_usd() do
      {:ok, %Decimal{} = reference} -> {:ok, reference}
      {:error, reason} -> {:error, {:reference_price_unavailable, reason}}
      _other -> {:error, :reference_price_invalid}
    end
  end

  defp price_band_guard(twap, reference) do
    lower = Decimal.mult(reference, Decimal.new(10_000 - @maximum_price_deviation_bps))
    upper = Decimal.mult(reference, Decimal.new(10_000 + @maximum_price_deviation_bps))
    scaled_twap = Decimal.mult(twap, Decimal.new(10_000))

    if Decimal.compare(scaled_twap, lower) != :lt and
         Decimal.compare(scaled_twap, upper) != :gt do
      :ok
    else
      {:error, :twap_outside_reference_band}
    end
  end

  defp minimum_output_guard(amount_raw, minimum_output_raw, reference) do
    amount_usdc = units_decimal(amount_raw, 6)
    minimum_output = units_decimal(minimum_output_raw, 18)
    implied_price = Decimal.div(amount_usdc, minimum_output)

    maximum_price =
      reference
      |> Decimal.mult(Decimal.new(10_000 + @maximum_price_deviation_bps))
      |> Decimal.div(Decimal.new(10_000))

    if Decimal.compare(implied_price, maximum_price) != :gt,
      do: :ok,
      else: {:error, :minimum_output_below_reference_floor}
  end

  defp subject(subject_id) do
    case Autolaunch.get_public_subject(subject_id, actor: nil) do
      {:ok, nil} -> {:error, :subject_not_found}
      result -> result
    end
  end

  defp base_chain(@base_chain_id), do: :ok
  defp base_chain(_chain_id), do: {:error, :unsupported_chain}

  defp stored_identity(%{resource: @resource} = envelope) do
    case argument(envelope, :subject_id) do
      subject_id when is_binary(subject_id) -> subject(subject_id)
      _ -> {:error, :invalid_subject_identity}
    end
  end

  defp stored_identity(_envelope), do: {:error, :invalid_resource}

  defp valid_for_confirmation?(envelope, subject) do
    with {:ok, router} <- normalize_address(subject.revenue_router_address),
         {:ok, treasury} <- normalize_address(subject.treasury_address),
         true <- argument(envelope, :revenue_router) == router,
         true <- argument(envelope, :treasury) == treasury,
         true <- is_nil(envelope.approval) do
      Envelope.valid_for_confirmation?(envelope,
        resource: @resource,
        to: router,
        signer: envelope.expected_signer,
        contract_name: @contract_name,
        action: @action
      )
    else
      _ -> false
    end
  end

  defp decimal_units(value, decimals) do
    with {:ok, decimal} <- positive_decimal(value) do
      scaled = Decimal.mult(decimal, Integer.pow(10, decimals))
      rounded = Decimal.round(scaled, 0)

      if Decimal.equal?(scaled, rounded) do
        valid_units(decimal, Decimal.to_integer(rounded))
      else
        {:error, :invalid_amount_precision}
      end
    end
  end

  defp valid_units(decimal, amount) when amount in 1..@uint256_max,
    do: {:ok, decimal, amount}

  defp valid_units(_decimal, _amount), do: {:error, :invalid_amount}

  defp attach_refreshed_subject(result, subject_id) do
    with {:ok, refreshed} <- subject(subject_id) do
      {:ok, Map.put(result, :subject, refreshed)}
    end
  end

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

  defp nonnegative_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} when integer >= 0 -> {:ok, integer}
      _ -> :error
    end
  end

  defp nonnegative_integer(_value), do: :error

  defp bytes32("0x" <> value = bytes32) when byte_size(value) == 64 do
    if String.match?(value, ~r/^[0-9a-fA-F]+$/),
      do: {:ok, String.downcase(bytes32)},
      else: {:error, :invalid_subject_identity}
  end

  defp bytes32(_value), do: {:error, :invalid_subject_identity}

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

  defp units_decimal(value, decimals),
    do: Decimal.div(Decimal.new(value), Decimal.new(Integer.pow(10, decimals)))

  defp decimal_string(decimal), do: decimal |> Decimal.normalize() |> Decimal.to_string(:normal)

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
