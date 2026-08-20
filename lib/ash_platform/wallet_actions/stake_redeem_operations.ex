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

  # The outcomes a verified transaction may end at. Whichever lands first under
  # the row lock is the only one that exists.
  @terminal [:confirmed, :unverified, :reverted]
  @unverified_reason "safe receipt without this action's event"
  @revert_reason %{
    approval: "verified approval revert on Base",
    action: "verified revert on Base"
  }

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
  Records one verified receipt and its outcome for a phase, under the row lock.

  Confirmed, unverified and reverted are all terminal winners: the lock
  serializes every one of them for an operation, exactly one exists, and a race
  or a late repeat of any callback is answered with the row's own outcome rather
  than an Ash validation error. A verified approval is not terminal, so it
  enables the action phase instead of ending the operation.
  """
  @spec settle(lease(), capability(), String.t(), phase(), :confirmed | :unverified | :reverted) ::
          {:ok, struct()} | {:error, term()}
  def settle(lease, capability, action_id, phase, outcome) do
    write(lease, capability, action_id, fn
      %{state: state} = terminal when state in @terminal -> {:ok, terminal}
      operation -> settle_phase(operation, capability, phase, outcome)
    end)
  end

  @doc """
  Settles one chain client's action-phase result and reports the row's outcome.

  A pending transaction writes nothing at all: its hash and state survive so the
  same hash can be read again later.
  """
  @spec settle_action({:ok, map()} | {:error, term()}, lease(), capability(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def settle_action({:ok, %{outcome: :pending} = result}, _lease, _capability, _action_id),
    do: {:ok, result}

  def settle_action({:ok, %{outcome: outcome} = result}, lease, capability, action_id) do
    with {:ok, operation} <- settle(lease, capability, action_id, :action, outcome),
         do: {:ok, %{result | outcome: operation.state}}
  end

  def settle_action({:error, reason}, _lease, _capability, _action_id), do: {:error, reason}

  defp settle_phase(operation, capability, phase, :reverted),
    do: transition(operation, capability, revert_action(phase), Map.fetch!(@revert_reason, phase))

  defp settle_phase(operation, capability, phase, outcome) do
    with {:ok, operation} <- transition(operation, capability, receipt_action(phase)),
         do: outcome_transition(operation, capability, phase, outcome)
  end

  defp outcome_transition(operation, capability, :approval, :confirmed),
    do: transition(operation, capability, :verify_approval)

  defp outcome_transition(operation, capability, :action, :confirmed),
    do: transition(operation, capability, :confirm)

  defp outcome_transition(operation, capability, _phase, :unverified),
    do: transition(operation, capability, :record_unverified, @unverified_reason)

  @doc """
  Withdraws a review before either dispatch, or after the approval is verified.

  A hashless claimed phase and a submitted-but-unverified approval stay open:
  a transaction that may yet land is never closed as though it had not.
  """
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

  @doc """
  Returns a claimed dispatch the browser proved never reached its wallet send.

  Only the hash-free dispatch for the exact claimed phase moves, so a hash that
  binds first wins and a released phase can no longer accept one. A verified
  approval survives untouched: the review resumes at the stake.
  """
  @spec release_unstarted(lease(), capability(), String.t(), phase()) ::
          {:ok, struct()} | {:error, term()}
  def release_unstarted(lease, capability, action_id, phase) do
    claimed = dispatched_state(phase)

    write(lease, capability, action_id, fn
      %{state: ^claimed} = operation ->
        transition(operation, capability, unstarted_release(operation))

      _other_phase ->
        {:error, :unstarted_phase_mismatch}
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

  @doc "The only operation facts a presenter restores from. Everything else stays server-side."
  @spec view(struct() | nil) :: map() | nil
  def view(nil), do: nil

  def view(operation) do
    Map.take(operation, [
      :action_id,
      :state,
      :envelope,
      :approval_transaction_hash,
      :action_transaction_hash
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

      # A typed Ash error, so the refusal survives the action's error class and
      # the presenter can say which fact holds the slot.
      {:ok, _dispatched} ->
        {:error,
         Ash.Error.Invalid.Unavailable.exception(
           resource: StakeRedeemOperation,
           reason: :operation_in_flight
         )}

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

  defp unstarted_release(%{state: :approval_dispatched}), do: :release_unstarted_approval
  defp unstarted_release(%{approval_transaction_hash: nil}), do: :release_unstarted_action
  defp unstarted_release(_verified_approval), do: :release_unstarted_action_after_approval

  defp domain(:stake), do: AshPlatform.Staking
  defp domain(:redeem), do: AshPlatform.Redemption
end
