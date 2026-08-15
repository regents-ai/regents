defmodule AshPlatform.WalletActions.StakeRedeemOperations do
  @moduledoc """
  The one private transition boundary for `StakeRedeemOperation`.

  Every durable write runs inside `SessionAuthority.transact_lease/3` as the
  outermost transaction, so a claim, a hash bind or a confirmation cannot outlive
  a concurrent logout, revocation or lapse of provider evidence. The owner comes
  from the account that callback locked rather than an actor captured earlier,
  and is rechecked against the prepared signer.

  Provider reads happen before these calls. Only the resulting row write happens
  inside the lock, and the row is taken `FOR UPDATE` first, so two sockets racing
  the same dispatch serialize and exactly one of them wins.

  Restore is the one read that needs no lease: it reads the owning account's
  active operation and writes nothing.
  """

  require Ash.Query

  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.Actors.System
  alias AshPlatform.WalletActions.{Address, Rpc, StakeRedeemOperation}

  @actor %System{}

  @type lease :: %{lineage: String.t(), account_id: integer()}
  @type capability :: :stake | :redeem
  @type phase :: :approval | :action

  @doc "Commits the prepared envelope as the operation the wallet handoff will need."
  @spec prepare(lease(), capability(), map()) :: {:ok, struct()} | {:error, term()}
  def prepare(lease, capability, envelope) do
    transact(lease, fn account ->
      with :ok <- signer_matches(account, envelope),
           :ok <- release_undispatched(account.id, capability) do
        StakeRedeemOperation
        |> Ash.Changeset.for_create(
          :prepare,
          %{
            action_id: envelope.action_id,
            capability: capability,
            action: envelope.action,
            envelope: envelope,
            human_account_id: account.id
          },
          domain: domain(capability),
          actor: @actor
        )
        |> Ash.create(actor: @actor)
      end
    end)
  end

  @doc "Atomically claims one phase's dispatch. Only this winner may open the wallet."
  @spec claim_dispatch(lease(), capability(), String.t(), phase()) ::
          {:ok, struct()} | {:error, term()}
  def claim_dispatch(lease, capability, action_id, phase) do
    write(lease, capability, action_id, &transition(&1, capability, claim_action(phase)))
  end

  @doc """
  Binds the first valid hash for a phase.

  An exact replay is an authority no-op so a retrying browser cannot fail, and a
  different hash is refused rather than overwriting the submitted identity.
  """
  @spec bind_hash(lease(), capability(), String.t(), phase(), String.t()) ::
          {:ok, struct()} | {:error, term()}
  def bind_hash(lease, capability, action_id, phase, hash) do
    write(lease, capability, action_id, &bind(&1, capability, phase, hash))
  end

  @doc """
  Records the exact successful receipt for a phase, which alone confirms nothing.

  A confirmed operation replays as an authority no-op, so a retrying browser or
  a late async result cannot fail against work that is already terminal.
  """
  @spec record_receipt(lease(), capability(), String.t(), phase()) ::
          {:ok, struct()} | {:error, term()}
  def record_receipt(lease, capability, action_id, phase) do
    write(lease, capability, action_id, fn
      %{state: :confirmed} = confirmed -> {:ok, confirmed}
      operation -> transition(operation, capability, receipt_action(phase))
    end)
  end

  @doc "Completes the approval phase once its receipt and the exact allowance both hold."
  @spec verify_approval(lease(), capability(), String.t()) :: {:ok, struct()} | {:error, term()}
  def verify_approval(lease, capability, action_id) do
    write(lease, capability, action_id, &transition(&1, capability, :verify_approval))
  end

  @doc """
  Terminal success: the exact receipt and the authoritative reread agree.

  Confirming an already-confirmed operation replays as an authority no-op.
  """
  @spec confirm(lease(), capability(), String.t()) :: {:ok, struct()} | {:error, term()}
  def confirm(lease, capability, action_id) do
    write(lease, capability, action_id, fn
      %{state: :confirmed} = confirmed -> {:ok, confirmed}
      operation -> transition(operation, capability, :confirm)
    end)
  end

  @doc "Terminal failure: the receipt for this phase says the transaction reverted."
  @spec record_revert(lease(), capability(), String.t(), phase(), String.t()) ::
          {:ok, struct()} | {:error, term()}
  def record_revert(lease, capability, action_id, phase, reason) do
    write(lease, capability, action_id, &transition(&1, capability, revert_action(phase), reason))
  end

  @doc "Withdraws a review nobody has dispatched."
  @spec cancel(lease(), capability(), String.t(), String.t()) ::
          {:ok, struct()} | {:error, term()}
  def cancel(lease, capability, action_id, reason) do
    write(lease, capability, action_id, &transition(&1, capability, :cancel, reason))
  end

  @doc """
  Closes a claimed but hash-free dispatch as never sent.

  Only the browser's exact EIP-1193 4001 for this action and phase reaches here.
  The phase is checked against the claim, so a rejection reported for the other
  phase cannot release this one.
  """
  @spec close_not_sent(lease(), capability(), String.t(), phase(), String.t()) ::
          {:ok, struct()} | {:error, term()}
  def close_not_sent(lease, capability, action_id, phase, reason) do
    claimed = dispatched_state(phase)

    write(lease, capability, action_id, fn
      %{state: ^claimed} = operation ->
        transition(operation, capability, :close_not_sent, reason)

      _other_phase ->
        {:error, :rejection_phase_mismatch}
    end)
  end

  @doc "The owning account's active operation, read without a lease and writing nothing."
  @spec active(integer(), capability()) :: {:ok, struct() | nil} | {:error, term()}
  def active(account_id, capability) do
    StakeRedeemOperation
    |> Ash.Query.for_read(:active, %{human_account_id: account_id, capability: capability},
      domain: domain(capability)
    )
    |> Ash.read_one(domain: domain(capability), actor: @actor)
  end

  @doc """
  The mounted lease an Ash action context carries, or the refusal to write at all.

  The lease travels in action context rather than in the actor, so the Human
  actor a policy sees is unchanged and nothing about the browser session leaks
  into an actor struct.
  """
  @spec lease(map()) :: {:ok, lease()} | {:error, :session_lease_required}
  def lease(%{source_context: %{session_lease: %{lineage: lineage, account_id: account_id}}})
      when is_binary(lineage) and is_integer(account_id),
      do: {:ok, %{lineage: lineage, account_id: account_id}}

  def lease(_context), do: {:error, :session_lease_required}

  @doc "The operation facts a presenter may hold. Timestamps and owner stay server-side."
  @spec view(struct() | nil) :: map() | nil
  def view(nil), do: nil

  def view(operation) do
    Map.take(operation, [
      :action_id,
      :capability,
      :action,
      :state,
      :envelope,
      :approval_transaction_hash,
      :action_transaction_hash,
      :reason
    ])
  end

  defp write(lease, capability, action_id, transition) do
    transact(lease, fn account ->
      with {:ok, operation} <- locked(account.id, capability, action_id) do
        transition.(operation)
      end
    end)
  end

  defp transact(%{lineage: lineage, account_id: account_id}, callback),
    do: SessionAuthority.transact_lease(lineage, account_id, callback)

  defp transact(_lease, _callback), do: {:error, :stale_authority}

  defp locked(account_id, capability, action_id) do
    StakeRedeemOperation
    |> Ash.Query.new(domain: domain(capability))
    |> Ash.Query.filter(
      action_id == ^action_id and human_account_id == ^account_id and capability == ^capability
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(domain: domain(capability), actor: @actor)
    |> case do
      {:ok, nil} -> {:error, :operation_not_found}
      other -> other
    end
  end

  defp locked_active(account_id, capability) do
    StakeRedeemOperation
    |> Ash.Query.for_read(:active, %{human_account_id: account_id, capability: capability},
      domain: domain(capability)
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(domain: domain(capability), actor: @actor)
  end

  # A new review may replace one nobody has dispatched; anything already claimed
  # holds the account's single active slot until it reaches a terminal state.
  defp release_undispatched(account_id, capability) do
    case locked_active(account_id, capability) do
      {:ok, nil} ->
        :ok

      {:ok, %{state: :prepared} = operation} ->
        with {:ok, _cancelled} <-
               transition(operation, capability, :cancel, "replaced by a newer review"),
             do: :ok

      {:ok, _dispatched} ->
        {:error, :operation_in_flight}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp bind(operation, capability, phase, hash) do
    with {:ok, hash} <- canonical_hash(hash) do
      case Map.fetch!(operation, hash_attribute(phase)) do
        nil ->
          transition(operation, capability, bind_action(phase), %{hash_attribute(phase) => hash})

        ^hash ->
          {:ok, operation}

        _different ->
          {:error, :submitted_hash_conflict}
      end
    end
  end

  defp transition(operation, capability, action),
    do: transition(operation, capability, action, %{})

  defp transition(operation, capability, action, reason) when is_binary(reason),
    do: transition(operation, capability, action, %{reason: reason})

  defp transition(operation, capability, action, input) do
    operation
    |> Ash.Changeset.for_update(action, input, domain: domain(capability), actor: @actor)
    |> Ash.update(actor: @actor)
  end

  defp signer_matches(account, %{expected_signer: signer}) do
    if Enum.any?(account.wallet_addresses || [], &Address.equal?(&1, signer)),
      do: :ok,
      else: {:error, :wrong_signer}
  end

  defp canonical_hash(hash) do
    if Rpc.valid_hash?(hash), do: {:ok, String.downcase(hash)}, else: {:error, :invalid_hash}
  end

  defp claim_action(:approval), do: :claim_approval_dispatch
  defp claim_action(:action), do: :claim_action_dispatch

  defp bind_action(:approval), do: :bind_approval_hash
  defp bind_action(:action), do: :bind_action_hash

  defp receipt_action(:approval), do: :record_approval_receipt
  defp receipt_action(:action), do: :record_action_receipt

  defp revert_action(:approval), do: :record_approval_revert
  defp revert_action(:action), do: :record_action_revert

  defp hash_attribute(:approval), do: :approval_transaction_hash
  defp hash_attribute(:action), do: :action_transaction_hash

  defp dispatched_state(:approval), do: :approval_dispatched
  defp dispatched_state(:action), do: :action_dispatched

  defp domain(:stake), do: AshPlatform.Staking
  defp domain(:redeem), do: AshPlatform.Redemption
end
