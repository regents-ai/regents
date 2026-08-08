defmodule AshPlatform.Autolaunch.SubjectPaymentActions do
  @moduledoc false

  alias AshPlatform.{Accounts, Autolaunch}
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.Autolaunch.{PaymentLink, SubjectPaymentChainClient}
  alias AshPlatform.WalletActions.{Abi, Envelope, SubjectPaymentAbi}

  @payment_link_resource "autolaunch_payment_link"
  @ingress_resource "autolaunch_ingress"
  @staking_resource "autolaunch_subject_staking"
  @payment_link_contract "PaymentLinkFactory"
  @ingress_contract "RevenueIngressAccount"
  @staking_contract "RevenueShareSplitterV2"
  @base_chain_id 8453
  @token_decimals 18
  @uint256_max Integer.pow(2, 256) - 1
  @zero_address "0x0000000000000000000000000000000000000000"
  @payment_link_actions ~w(
    create_payment_link
    create_canonical_payment_link
    set_payment_link_canonical
    set_payment_link_receiver_state
  )
  @staking_actions ~w(stake unstake claim_usdc)
  @risk %{
    "create_payment_link" => "Create a payment link for this subject from the stored factory.",
    "create_canonical_payment_link" =>
      "Create a canonical payment link for this subject from the stored factory.",
    "set_payment_link_canonical" =>
      "Change whether this payment link is canonical for the subject.",
    "set_payment_link_receiver_state" =>
      "Change whether this payment link receives funds and where inactive payments redirect.",
    "sweep_usdc" =>
      "Sweep held USDC from this recorded ingress account to the subject revenue splitter.",
    "stake" =>
      "Approve the exact subject-token amount, then stake it in the subject revenue splitter.",
    "unstake" => "Unstake this subject token amount and return it to your verified wallet.",
    "claim_usdc" => "Claim available subject revenue in USDC to your verified wallet."
  }

  def prepare_payment_link(subject_id, signer, label, canonical, opts) do
    with :ok <- action_not_admitted(),
         {:ok, subject, signer, subject_bytes32} <- prepare_context(subject_id, signer, opts),
         {:ok, factory} <- normalize_address(subject.factory_address),
         {:ok, label} <- label(label),
         {:ok, canonical} <- boolean(canonical),
         salt <- random_bytes32(),
         {:ok, data} <-
           encode(fn ->
             SubjectPaymentAbi.encode_payment_link_create(
               subject_bytes32,
               label,
               salt,
               canonical
             )
           end) do
      action =
        if canonical, do: "create_canonical_payment_link", else: "create_payment_link"

      {:ok,
       envelope(action, signer, data, factory,
         resource: @payment_link_resource,
         contract_name: @payment_link_contract,
         arguments: %{
           subject_id: subject.subject_id,
           factory: factory,
           label: label,
           canonical: canonical,
           salt: salt
         }
       )}
    end
  end

  def prepare_payment_link_canonical(subject_id, signer, receiver, canonical, opts) do
    with :ok <- action_not_admitted(),
         {:ok, subject, signer, _subject_bytes32} <- prepare_context(subject_id, signer, opts),
         {:ok, factory} <- normalize_address(subject.factory_address),
         {:ok, receiver} <- allowed_payment_link_receiver(subject, receiver),
         {:ok, canonical} <- boolean(canonical),
         {:ok, data} <-
           encode(fn ->
             SubjectPaymentAbi.encode_payment_link_canonical(receiver, canonical)
           end) do
      {:ok,
       envelope("set_payment_link_canonical", signer, data, factory,
         resource: @payment_link_resource,
         contract_name: @payment_link_contract,
         arguments: %{
           subject_id: subject.subject_id,
           factory: factory,
           receiver: receiver,
           canonical: canonical
         }
       )}
    end
  end

  def prepare_payment_link_state(
        subject_id,
        signer,
        receiver,
        active,
        replacement,
        opts
      ) do
    with :ok <- action_not_admitted(),
         {:ok, subject, signer, _subject_bytes32} <- prepare_context(subject_id, signer, opts),
         {:ok, factory} <- normalize_address(subject.factory_address),
         {:ok, receiver} <- allowed_payment_link_receiver(subject, receiver),
         {:ok, active} <- boolean(active),
         {:ok, replacement} <- optional_address(replacement),
         :ok <- replacement_not_receiver(receiver, replacement),
         {:ok, data} <-
           encode(fn ->
             SubjectPaymentAbi.encode_payment_link_state(receiver, active, replacement)
           end) do
      {:ok,
       envelope("set_payment_link_receiver_state", signer, data, factory,
         resource: @payment_link_resource,
         contract_name: @payment_link_contract,
         arguments: %{
           subject_id: subject.subject_id,
           factory: factory,
           receiver: receiver,
           active: active,
           replacement: replacement
         }
       )}
    end
  end

  def prepare_ingress_sweep(subject_id, signer, ingress_address, opts) do
    with :ok <- action_not_admitted(),
         {:ok, subject, signer, subject_bytes32} <- prepare_context(subject_id, signer, opts),
         {:ok, ingress} <- allowed_ingress(subject, ingress_address),
         {:ok, data} <- encode(fn -> SubjectPaymentAbi.encode_ingress_sweep(subject_bytes32) end) do
      {:ok,
       envelope("sweep_usdc", signer, data, ingress,
         resource: @ingress_resource,
         contract_name: @ingress_contract,
         arguments: %{
           subject_id: subject.subject_id,
           ingress_account: ingress,
           source_ref: subject_bytes32
         }
       )}
    end
  end

  def prepare_stake(subject_id, signer, amount, receiver, opts) do
    with :ok <- action_not_admitted(),
         {:ok, subject, signer, _subject_bytes32} <- prepare_context(subject_id, signer, opts),
         {:ok, splitter} <- normalize_address(subject.splitter_address),
         {:ok, token} <- normalize_address(subject.token_address),
         {:ok, amount_decimal, amount_atomic} <- decimal_units(amount),
         {:ok, receiver} <- receiver(receiver, signer),
         {:ok, data} <- encode(fn -> SubjectPaymentAbi.encode_stake(amount_atomic, receiver) end),
         {:ok, approval_data} <-
           encode(fn -> SubjectPaymentAbi.encode_approval(splitter, amount_atomic) end) do
      approval = %{
        token: token,
        spender: splitter,
        amount: Integer.to_string(amount_atomic),
        data: approval_data,
        mode: "exact"
      }

      {:ok,
       envelope("stake", signer, data, splitter,
         resource: @staking_resource,
         contract_name: @staking_contract,
         approval: approval,
         arguments: %{
           subject_id: subject.subject_id,
           splitter: splitter,
           token: token,
           amount: decimal_string(amount_decimal),
           amount_atomic: Integer.to_string(amount_atomic),
           receiver: receiver
         }
       )}
    end
  end

  def prepare_unstake(subject_id, signer, amount, opts) do
    with :ok <- action_not_admitted(),
         {:ok, subject, signer, _subject_bytes32} <- prepare_context(subject_id, signer, opts),
         {:ok, splitter} <- normalize_address(subject.splitter_address),
         {:ok, amount_decimal, amount_atomic} <- decimal_units(amount),
         {:ok, data} <-
           encode(fn -> SubjectPaymentAbi.encode_unstake(amount_atomic, signer) end) do
      {:ok,
       envelope("unstake", signer, data, splitter,
         resource: @staking_resource,
         contract_name: @staking_contract,
         arguments: %{
           subject_id: subject.subject_id,
           splitter: splitter,
           amount: decimal_string(amount_decimal),
           amount_atomic: Integer.to_string(amount_atomic),
           recipient: signer
         }
       )}
    end
  end

  def prepare_claim_usdc(subject_id, signer, opts) do
    with :ok <- action_not_admitted(),
         {:ok, subject, signer, _subject_bytes32} <- prepare_context(subject_id, signer, opts),
         {:ok, splitter} <- normalize_address(subject.splitter_address),
         {:ok, data} <- encode(fn -> SubjectPaymentAbi.encode_claim_usdc(signer) end) do
      {:ok,
       envelope("claim_usdc", signer, data, splitter,
         resource: @staking_resource,
         contract_name: @staking_contract,
         arguments: %{
           subject_id: subject.subject_id,
           splitter: splitter,
           recipient: signer
         }
       )}
    end
  end

  def confirm(envelope, transaction_hash, approval_transaction_hash, opts) do
    actor = Keyword.get(opts, :actor)
    envelope = atomize_envelope(envelope)

    with %Human{} <- actor,
         {:ok, subject} <- stored_identity(envelope),
         :ok <- owner(subject, envelope.expected_signer),
         true <- valid_for_confirmation?(envelope, subject),
         :ok <- verified_wallet(actor, envelope.expected_signer) do
      case SubjectPaymentChainClient.module().confirm(
             envelope,
             transaction_hash,
             approval_transaction_hash
           ) do
        {:ok, result} ->
          complete_confirmation(envelope, subject, result)

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
         {:ok, subject} <- stored_identity(envelope),
         :ok <- owner(subject, envelope.expected_signer),
         true <- valid_for_confirmation?(envelope, subject),
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
         {:ok, subject} <- stored_identity(envelope),
         :ok <- owner(subject, envelope.expected_signer),
         true <- valid_for_confirmation?(envelope, subject),
         :ok <- verified_wallet(actor, envelope.expected_signer) do
      SubjectPaymentChainClient.module().approval_status(envelope, transaction_hash)
    else
      _ -> {:error, :invalid_submitted_action}
    end
  end

  defp action_not_admitted, do: {:error, :action_not_admitted}

  defp prepare_context(subject_id, signer, opts) do
    actor = Keyword.get(opts, :actor)

    with %Human{} <- actor,
         {:ok, signer} <- normalize_address(signer),
         :ok <- verified_wallet(actor, signer),
         {:ok, subject} <- subject(subject_id),
         :ok <- base_chain(subject.chain_id),
         :ok <- owner(subject, signer),
         {:ok, subject_bytes32} <- bytes32(subject.subject_id) do
      {:ok, subject, signer, subject_bytes32}
    else
      nil -> {:error, :authentication_required}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :authentication_required}
    end
  end

  defp subject(subject_id) do
    case Autolaunch.get_public_subject(subject_id, actor: nil) do
      {:ok, nil} -> {:error, :subject_not_found}
      result -> result
    end
  end

  defp stored_identity(%{resource: resource} = envelope)
       when resource in [
              @payment_link_resource,
              @ingress_resource,
              @staking_resource
            ] do
    case argument(envelope, :subject_id) do
      subject_id when is_binary(subject_id) -> subject(subject_id)
      _ -> {:error, :invalid_subject_identity}
    end
  end

  defp stored_identity(_envelope), do: {:error, :invalid_resource}

  defp valid_for_confirmation?(
         %{resource: @payment_link_resource, action: action} = envelope,
         subject
       )
       when action in @payment_link_actions do
    with {:ok, factory} <- normalize_address(subject.factory_address),
         true <- argument(envelope, :factory) == factory,
         true <- valid_payment_link_receiver?(envelope, subject),
         true <- is_nil(envelope.approval) do
      valid_envelope?(envelope, @payment_link_resource, factory, @payment_link_contract,
        actions: @payment_link_actions
      )
    else
      _ -> false
    end
  end

  defp valid_for_confirmation?(
         %{resource: @ingress_resource, action: "sweep_usdc"} = envelope,
         subject
       ) do
    with {:ok, ingress} <- allowed_ingress(subject, envelope.to),
         true <- argument(envelope, :ingress_account) == ingress,
         true <- is_nil(envelope.approval) do
      valid_envelope?(
        envelope,
        @ingress_resource,
        ingress,
        @ingress_contract,
        action: "sweep_usdc"
      )
    else
      _ -> false
    end
  end

  defp valid_for_confirmation?(
         %{resource: @staking_resource, action: action} = envelope,
         subject
       )
       when action in @staking_actions do
    with {:ok, splitter} <- normalize_address(subject.splitter_address),
         true <- argument(envelope, :splitter) == splitter,
         true <- valid_staking_approval?(envelope, subject) do
      valid_envelope?(envelope, @staking_resource, splitter, @staking_contract,
        actions: @staking_actions
      )
    else
      _ -> false
    end
  end

  defp valid_for_confirmation?(_envelope, _subject), do: false

  defp valid_staking_approval?(%{action: "stake", approval: approval} = envelope, subject)
       when is_map(approval) do
    with {:ok, token} <- normalize_address(subject.token_address),
         {:ok, amount} <- nonnegative_integer(argument(envelope, :amount_atomic)),
         true <- amount > 0,
         true <- field(approval, :token) == token,
         true <- field(approval, :spender) == envelope.to,
         true <- field(approval, :amount) == Integer.to_string(amount),
         true <- field(approval, :mode) == "exact",
         true <- field(approval, :data) == SubjectPaymentAbi.encode_approval(envelope.to, amount) do
      true
    else
      _ -> false
    end
  end

  defp valid_staking_approval?(%{action: action, approval: nil}, _subject)
       when action in ~w(unstake claim_usdc),
       do: true

  defp valid_staking_approval?(_envelope, _subject), do: false

  defp valid_envelope?(envelope, resource, to, contract_name, action_opts) do
    Envelope.valid_for_confirmation?(
      envelope,
      [resource: resource, to: to, signer: envelope.expected_signer, contract_name: contract_name] ++
        action_opts
    )
  end

  defp allowed_ingress(subject, requested),
    do: allowed_recorded_address(subject.ingress_address, requested, :ingress_not_recorded)

  defp allowed_payment_link_receiver(subject, requested),
    do: recorded_payment_link_receiver(subject, requested)

  defp allowed_recorded_address(recorded, requested, not_recorded_error) do
    with {:ok, requested} <- normalize_address(requested),
         addresses <-
           [recorded]
           |> Enum.map(&normalize_or_nil/1)
           |> Enum.reject(&is_nil/1)
           |> Enum.uniq(),
         true <- requested in addresses do
      {:ok, requested}
    else
      false -> {:error, not_recorded_error}
      {:error, reason} -> {:error, reason}
    end
  end

  defp recorded_payment_link_receiver(subject, requested) do
    with {:ok, requested} <- normalize_address(requested),
         {:ok, %PaymentLink{}} <-
           PaymentLink
           |> Ash.Query.for_read(
             :by_subject_and_receiver,
             %{subject_id: subject.id, receiver_address: requested},
             actor: %System{}
           )
           |> Ash.read_one() do
      {:ok, requested}
    else
      {:ok, nil} -> {:error, :payment_link_receiver_not_recorded}
      {:error, :invalid_address} = error -> error
      {:error, _error} -> {:error, :payment_link_receiver_lookup_failed}
    end
  end

  defp valid_payment_link_receiver?(
         %{action: action},
         _subject
       )
       when action in ~w(create_payment_link create_canonical_payment_link),
       do: true

  defp valid_payment_link_receiver?(
         %{action: action} = envelope,
         subject
       )
       when action in ~w(set_payment_link_canonical set_payment_link_receiver_state) do
    with {:ok, receiver} <-
           allowed_payment_link_receiver(subject, argument(envelope, :receiver)),
         true <- receiver == argument(envelope, :receiver),
         :ok <-
           valid_payment_link_replacement(
             action,
             receiver,
             argument(envelope, :replacement)
           ) do
      true
    else
      _ -> false
    end
  end

  defp valid_payment_link_receiver?(_envelope, _subject), do: false

  defp valid_payment_link_replacement("set_payment_link_receiver_state", receiver, replacement),
    do: replacement_not_receiver(receiver, replacement)

  defp valid_payment_link_replacement("set_payment_link_canonical", _receiver, nil), do: :ok
  defp valid_payment_link_replacement(_action, _receiver, _replacement), do: {:error, :invalid}

  defp replacement_not_receiver(receiver, receiver), do: {:error, :replacement_matches_receiver}
  defp replacement_not_receiver(_receiver, _replacement), do: :ok

  defp owner(subject, signer) do
    owners =
      [subject.creator_address, subject.treasury_address]
      |> Enum.map(&normalize_or_nil/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if signer in owners, do: :ok, else: {:error, :not_subject_owner}
  end

  defp base_chain(@base_chain_id), do: :ok
  defp base_chain(_chain_id), do: {:error, :unsupported_chain}

  defp label(value) when is_binary(value) do
    value = String.trim(value)

    if value != "" and byte_size(value) <= 96,
      do: {:ok, value},
      else: {:error, :invalid_label}
  end

  defp label(_value), do: {:error, :invalid_label}

  defp boolean(value) when is_boolean(value), do: {:ok, value}
  defp boolean(_value), do: {:error, :invalid_boolean}

  defp random_bytes32,
    do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)

  defp bytes32("0x" <> value = bytes32) when byte_size(value) == 64 do
    if String.match?(value, ~r/^[0-9a-fA-F]+$/) and value != String.duplicate("0", 64),
      do: {:ok, String.downcase(bytes32)},
      else: {:error, :invalid_bytes32}
  end

  defp bytes32(_value), do: {:error, :invalid_bytes32}

  defp optional_address(value) when value in [nil, ""], do: {:ok, @zero_address}
  defp optional_address(value), do: normalize_address(value)

  defp receiver(value, signer) when value in [nil, ""], do: {:ok, signer}
  defp receiver(value, _signer), do: normalize_address(value)

  defp decimal_units(value) do
    with {:ok, decimal} <- positive_decimal(value) do
      scaled = Decimal.mult(decimal, Integer.pow(10, @token_decimals))
      rounded = Decimal.round(scaled, 0)

      if Decimal.equal?(scaled, rounded) do
        valid_decimal_units(decimal, Decimal.to_integer(rounded))
      else
        {:error, :invalid_amount_precision}
      end
    end
  end

  defp valid_decimal_units(decimal, amount) when amount in 1..@uint256_max,
    do: {:ok, decimal, amount}

  defp valid_decimal_units(_decimal, _amount), do: {:error, :invalid_amount}

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
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> {:ok, integer}
      _ -> {:error, :invalid_amount}
    end
  end

  defp nonnegative_integer(_value), do: {:error, :invalid_amount}

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

  defp envelope(action, signer, data, to, opts) do
    Envelope.new(action, signer, data,
      to: to,
      resource: Keyword.fetch!(opts, :resource),
      contract_name: Keyword.fetch!(opts, :contract_name),
      risk_copy: Map.fetch!(@risk, action),
      approval: Keyword.get(opts, :approval),
      arguments: Keyword.fetch!(opts, :arguments)
    )
  end

  defp attach_refreshed_subject(result, subject_id) do
    with {:ok, refreshed} <- subject(subject_id) do
      {:ok, Map.put(result, :subject, refreshed)}
    end
  end

  defp complete_confirmation(envelope, subject, result) do
    with {:ok, result} <- record_confirmed_payment_link(envelope, subject, result) do
      attach_refreshed_subject(result, subject.subject_id)
    end
  end

  defp record_confirmed_payment_link(
         %{action: action} = envelope,
         subject,
         result
       )
       when action in ~w(create_payment_link create_canonical_payment_link) do
    with {:ok, receiver} <- normalize_address(field(result, :payment_link_receiver)),
         {:ok, payment_link} <-
           PaymentLink
           |> Ash.Changeset.for_create(
             :record_confirmation,
             %{
               subject_id: subject.id,
               receiver_address: receiver,
               label: argument(envelope, :label)
             },
             actor: %System{}
           )
           |> Ash.create(),
         true <- payment_link.subject_id == subject.id,
         true <- payment_link.receiver_address == receiver,
         true <- payment_link.label == argument(envelope, :label) do
      {:ok, Map.put(result, :payment_link, payment_link)}
    else
      false -> {:error, :payment_link_confirmation_mismatch}
      {:error, :invalid_address} -> {:error, :payment_link_confirmation_mismatch}
      {:error, _error} -> {:error, :payment_link_persistence_failed}
    end
  end

  defp record_confirmed_payment_link(_envelope, _subject, result), do: {:ok, result}

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
