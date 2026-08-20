defmodule AshPlatform.Redemption.Actions do
  @moduledoc false

  alias AshPlatform.Accounts
  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.Actors.Human
  alias AshPlatform.Redemption.ChainClient
  alias AshPlatform.WalletActions.{Abi, Address, Envelope, RedemptionAbi, StakeRedeemOperations}

  @capability :redeem
  @rejection_reason "wallet reported an explicit user rejection"
  @withdrawal_reason "review withdrawn"

  # A Base read that may answer differently later. Everything else refuses for
  # good, so only these keep a submitted transaction open for another attempt.
  @transient [:chain_unavailable, :chain_timeout, :invalid_chain_response, :invalid_block_header]
  @resource "animata_redemption"
  @actions ~w(approve_nft_collection approve_exact_usdc redeem claim)
  @risk %{
    "approve_nft_collection" =>
      "Allow the verified Animata redeemer to transfer NFTs from this collection. This approval applies to the whole selected collection until you revoke it.",
    "approve_exact_usdc" =>
      "Approve exactly 80 USDC for the verified Animata redeemer. This replaces the current allowance with 80 USDC.",
    "redeem" =>
      "Transfer the selected Animata NFT and exactly 80 USDC to start a seven-day stream of 5 million REGENT and receive the mapped Regents Club token.",
    "claim" => "Claim all REGENT currently unlocked from your redemption vest."
  }

  def overview(_input, _context), do: ChainClient.module().overview(nil, nil, nil)

  # The active wallet alone decides which private facts this page may read.
  # Membership is a session fact, not a chain fact, so the reported wallet is
  # proved against the account the mounted lease resolves to and no provider is
  # read to do it.
  def account_for_wallet(input, %{actor: %Human{}} = context) do
    with {:ok, signer} <- current_wallet(input.arguments.expected_signer, context),
         {:ok, collection} <-
           optional_collection(input.arguments.collection, input.arguments.token_id) do
      ChainClient.module().overview(signer, collection, input.arguments.token_id)
    end
  end

  def account_for_wallet(_input, _context), do: {:error, :authentication_required}

  defp current_wallet(address, context) do
    with {:ok, signer} <- normalize_address(address),
         {:ok, lease} <- StakeRedeemOperations.lease(context),
         :ok <- leased_wallet(lease, signer),
         do: {:ok, signer}
  end

  # The provider reads happen here, before the lease transaction; only the
  # resulting operation row is written inside it.
  def prepare(action, input, %{actor: %Human{}} = context) do
    with {:ok, signer} <- normalize_address(input.arguments.expected_signer),
         {:ok, lease} <- StakeRedeemOperations.lease(context),
         :ok <- leased_wallet(lease, signer),
         {:ok, envelope} <- prepare_action(action, input.arguments, signer),
         {:ok, _operation} <- StakeRedeemOperations.prepare(lease, @capability, envelope) do
      {:ok, envelope}
    end
  end

  def prepare(_action, _input, _context), do: {:error, :authentication_required}

  def confirm(input, %{actor: %Human{} = actor} = context) do
    envelope = atomize_envelope(input.arguments.envelope)

    with {:ok, target, contract_name} <- identity_for(envelope),
         true <- valid_for_confirmation?(envelope, target, contract_name),
         :ok <- verified_wallet(actor, envelope.expected_signer),
         {:ok, lease} <- StakeRedeemOperations.lease(context),
         # Confirmation and every retry run against the stored submitted
         # identity: an exact replay passes, a different hash is refused.
         {:ok, _identity} <-
           StakeRedeemOperations.bind_hash(
             lease,
             @capability,
             envelope.action_id,
             :action,
             input.arguments.transaction_hash
           ) do
      envelope
      |> ChainClient.module().confirm(input.arguments.transaction_hash)
      |> transient_refusal()
      |> StakeRedeemOperations.settle_action(lease, @capability, envelope.action_id)
    else
      false -> {:error, :stale_or_invalid_action}
      {:error, reason} -> {:error, reason}
    end
  end

  def confirm(_input, _context), do: {:error, :authentication_required}

  # A read that may answer differently later becomes the typed refusal the page
  # retries; every other refusal is settled and says so instead.
  defp transient_refusal({:error, reason}) when reason in @transient,
    do: refusal(:chain_unavailable)

  defp transient_refusal(result), do: result

  # The reviewed action, both exact current approvals and the account's current
  # membership all decide this dispatch together. The provider reads happen here,
  # before the lease transaction; only the claim itself happens inside it.
  @doc false
  def claim_dispatch(%{arguments: %{envelope: envelope}}, %{actor: %Human{}} = context) do
    envelope = atomize_envelope(envelope)

    with {:ok, target, contract_name} <- identity_for(envelope),
         true <- valid_for_confirmation?(envelope, target, contract_name),
         :ok <- dispatch_approvals(envelope),
         {:ok, lease} <- StakeRedeemOperations.lease(context),
         :ok <- leased_wallet(lease, envelope.expected_signer),
         {:ok, operation} <-
           StakeRedeemOperations.claim_dispatch(lease, @capability, envelope.action_id, :action) do
      {:ok, %{operation: StakeRedeemOperations.view(operation)}}
    else
      false -> {:error, :stale_or_invalid_action}
      {:error, reason} -> {:error, reason}
    end
  end

  def claim_dispatch(_input, _context), do: {:error, :authentication_required}

  # Redeem spends both approvals, so both have to be current on a fresh safe
  # snapshot at the moment this dispatch is claimed. If either changed, nothing
  # is claimed and the review stays re-preparable.
  defp dispatch_approvals(envelope) do
    case ChainClient.module().approval_current(envelope) do
      :ok -> :ok
      {:error, reason} when reason in @transient -> refusal(:chain_unavailable)
      {:error, _changed} -> refusal(:approval_changed)
    end
  end

  @doc false
  def bind_hash(%{arguments: %{action_id: id, transaction_hash: hash}}, context),
    do: operate(context, &StakeRedeemOperations.bind_hash(&1, @capability, id, :action, hash))

  @doc false
  def close_not_sent(%{arguments: %{action_id: id}}, context),
    do:
      operate(
        context,
        &StakeRedeemOperations.close_not_sent(&1, @capability, id, :action, @rejection_reason)
      )

  @doc false
  def release_unstarted(%{arguments: %{action_id: id}}, context),
    do: operate(context, &StakeRedeemOperations.release_unstarted(&1, @capability, id, :action))

  @doc false
  def cancel_operation(%{arguments: %{action_id: id}}, context),
    do: operate(context, &StakeRedeemOperations.cancel(&1, @capability, id, @withdrawal_reason))

  @doc false
  def active_operation(_input, %{actor: %Human{} = actor}) do
    with {:ok, operation} <- StakeRedeemOperations.active(actor.human_account_id, @capability),
         do: {:ok, %{operation: StakeRedeemOperations.view(operation)}}
  end

  def active_operation(_input, _context), do: {:error, :authentication_required}

  defp operate(%{actor: %Human{}} = context, transition) do
    with {:ok, lease} <- StakeRedeemOperations.lease(context),
         {:ok, operation} <- transition.(lease) do
      {:ok, %{operation: StakeRedeemOperations.view(operation)}}
    end
  end

  defp operate(_context, _transition), do: {:error, :authentication_required}

  def restore(input, %{actor: %Human{} = actor}) do
    envelope = atomize_envelope(input.arguments.envelope)

    with {:ok, target, contract_name} <- identity_for(envelope),
         true <- valid_for_confirmation?(envelope, target, contract_name),
         :ok <- verified_wallet(actor, envelope.expected_signer) do
      {:ok, envelope}
    else
      _ -> {:error, :invalid_submitted_action}
    end
  end

  def restore(_input, _context), do: {:error, :authentication_required}

  defp prepare_action("approve_nft_collection", arguments, signer) do
    with {:ok, collection} <- RedemptionAbi.collection(arguments.collection) do
      redeemer = Abi.normalize_address!(RedemptionAbi.redeemer_address())
      data = RedemptionAbi.encode_erc721("set_approval_for_all", [redeemer, true])

      {:ok,
       Envelope.new("approve_nft_collection", signer, data,
         resource: @resource,
         to: collection,
         contract_name: collection_name(collection),
         risk_copy: @risk["approve_nft_collection"],
         arguments: %{collection: collection, operator: redeemer, approved: true}
       )}
    end
  end

  defp prepare_action("approve_exact_usdc", _arguments, signer) do
    redeemer = Abi.normalize_address!(RedemptionAbi.redeemer_address())
    usdc = Abi.normalize_address!(RedemptionAbi.usdc_address())
    amount = String.to_integer(RedemptionAbi.price_atomic())
    data = RedemptionAbi.encode_erc20("approve", [redeemer, amount])

    {:ok,
     Envelope.new("approve_exact_usdc", signer, data,
       resource: @resource,
       to: usdc,
       contract_name: "USDC",
       risk_copy: @risk["approve_exact_usdc"],
       arguments: %{
         spender: redeemer,
         amount_atomic: Integer.to_string(amount),
         mode: "exact"
       }
     )}
  end

  defp prepare_action("redeem", arguments, signer) do
    with {:ok, collection} <- RedemptionAbi.collection(arguments.collection),
         :ok <- valid_token_id(arguments.token_id),
         {:ok, facts} <- ChainClient.module().overview(signer, collection, arguments.token_id),
         :ok <- eligible_to_redeem(facts, signer) do
      data = RedemptionAbi.encode_action("redeem", [collection, arguments.token_id])

      {:ok,
       Envelope.new("redeem", signer, data,
         resource: @resource,
         to: RedemptionAbi.redeemer_address(),
         contract_name: "AnimataRedeemer",
         risk_copy: @risk["redeem"],
         arguments: %{collection: collection, token_id: arguments.token_id}
       )}
    end
  end

  defp prepare_action("claim", _arguments, signer) do
    with {:ok, facts} <- ChainClient.module().overview(signer, nil, nil),
         :ok <- positive_claimable(facts) do
      {:ok,
       Envelope.new("claim", signer, RedemptionAbi.encode_action("claim", []),
         resource: @resource,
         to: RedemptionAbi.redeemer_address(),
         contract_name: "AnimataRedeemer",
         risk_copy: @risk["claim"],
         arguments: %{}
       )}
    end
  end

  defp prepare_action(_action, _arguments, _signer), do: {:error, :unknown_action}

  defp eligible_to_redeem(facts, signer) do
    case next_step(facts, signer) do
      :ready -> :ok
      reason -> refusal(reason)
    end
  end

  @doc """
  The single next thing this redemption needs, as the exact reason it needs it.

  The server's eligibility ladder and the page's next step are this one function,
  so they can never disagree about what comes next: selection, then whichever
  approval is missing, then the redemption itself. An owner that could not be
  read says nothing about who owns the token and is never reported as someone
  else owning it, and a value that could not be read is unavailable evidence
  rather than a balance of nothing.
  """
  @spec next_step(map(), String.t() | nil) :: atom()
  def next_step(%{token_id: nil}, _signer), do: :token_selection_required
  def next_step(%{nft_owner_unavailable: true}, _signer), do: :nft_owner_unavailable

  def next_step(facts, signer) do
    price = String.to_integer(RedemptionAbi.price_atomic())

    with {:ok, allowance} <- atomic(facts.usdc_allowance_raw),
         {:ok, balance} <- atomic(facts.usdc_balance_raw) do
      cond do
        not Address.equal?(facts.nft_owner, signer) -> :nft_not_owned
        facts.nft_approved != true -> :nft_approval_required
        allowance != price -> :exact_usdc_approval_required
        balance < price -> :insufficient_usdc
        true -> :ready
      end
    else
      :error -> :chain_unavailable
    end
  end

  defp positive_claimable(facts) do
    case atomic(facts.claimable_raw) do
      {:ok, claimable} when claimable > 0 -> :ok
      {:ok, _nothing} -> refusal(:nothing_claimable)
      :error -> refusal(:chain_unavailable)
    end
  end

  defp valid_token_id(token_id)
       when is_integer(token_id) and token_id >= 1 and token_id <= 999,
       do: :ok

  defp valid_token_id(_token_id), do: {:error, :invalid_token_id}

  defp optional_collection(nil, nil), do: {:ok, nil}

  defp optional_collection(collection, nil) when is_binary(collection),
    do: RedemptionAbi.collection(collection)

  defp optional_collection(collection, token_id) when is_integer(token_id),
    do: RedemptionAbi.collection(collection)

  defp optional_collection(_collection, _token_id), do: {:error, :invalid_token_selection}

  defp identity_for(%{action: "approve_nft_collection", arguments: arguments}) do
    collection = field(arguments, :collection)

    case RedemptionAbi.collection_id(collection) do
      nil -> {:error, :invalid_collection}
      _id -> {:ok, Abi.normalize_address!(collection), collection_name(collection)}
    end
  end

  defp identity_for(%{action: "approve_exact_usdc"}),
    do: {:ok, Abi.normalize_address!(RedemptionAbi.usdc_address()), "USDC"}

  defp identity_for(%{action: action}) when action in ["redeem", "claim"],
    do: {:ok, Abi.normalize_address!(RedemptionAbi.redeemer_address()), "AnimataRedeemer"}

  defp identity_for(_envelope), do: {:error, :invalid_action}

  defp valid_for_confirmation?(envelope, target, contract_name) do
    Envelope.valid_for_confirmation?(envelope,
      resource: @resource,
      to: target,
      signer: envelope.expected_signer,
      contract_name: contract_name,
      actions: @actions
    )
  end

  # The lease, not the actor captured at mount, decides which account the
  # reviewed wallet has to belong to.
  defp leased_wallet(%{lineage: lineage, account_id: account_id}, signer),
    do: lineage |> SessionAuthority.leased_account(account_id) |> wallet_member(signer)

  defp wallet_member(nil, _signer), do: refusal(:session_unavailable)

  defp wallet_member(%{wallet_addresses: wallets}, signer) do
    if Enum.any?(wallets || [], &Address.equal?(&1, signer)),
      do: :ok,
      else: refusal(:wrong_signer)
  end

  # A typed Ash error, so the refusal survives the action's error class and the
  # presenter can name the fact that actually stopped the review.
  defp refusal(reason),
    do:
      {:error,
       Ash.Error.Invalid.Unavailable.exception(
         resource: AshPlatform.Redemption.Snapshot,
         reason: reason
       )}

  defp verified_wallet(%Human{} = actor, signer) do
    with {:ok, account} <- Accounts.get_human_account(actor.human_account_id, actor: actor),
         wallets when is_list(wallets) <- account.wallet_addresses,
         true <- Enum.any?(wallets, &Address.equal?(&1, signer)) do
      :ok
    else
      _ -> {:error, :wrong_signer}
    end
  end

  defp normalize_address(value) do
    with :error <- Address.normalize(value), do: {:error, :invalid_wallet}
  end

  defp atomic(value) do
    case Integer.parse(value || "") do
      {amount, ""} -> {:ok, amount}
      _unavailable -> :error
    end
  end

  defp collection_name(collection) do
    case RedemptionAbi.collection_id(collection) do
      "animata_i" -> "Animata I"
      "animata_ii" -> "Animata II"
    end
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
      arguments: atomize_arguments(field(envelope, :arguments) || %{}),
      metadata: field(envelope, :metadata),
      confirmation_token: field(envelope, :confirmation_token)
    }
  end

  defp atomize_arguments(arguments) when is_map(arguments) do
    Map.new(arguments, fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      pair -> pair
    end)
  rescue
    _ -> %{}
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
