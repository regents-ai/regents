defmodule AshPlatform.WalletActions.StakeRedeemOperation do
  @moduledoc """
  One durable Stake or Redeem operation the server owns before any wallet opens.

  The database, not the socket, decides every race. `action_id` is unique and
  immutable, each submitted hash is unique among the hashes that exist, and a
  partial unique identity over `terminal_at IS NULL` allows one active operation
  per human account and capability — deliberately serializing all Stake actions
  against each other and all Redeem actions against each other.

  Dispatch and submission are separate facts per phase. A claimed phase remains
  uncertain unless the wallet rejects its send or the browser proves that send
  never began; rejection closes it, while proven non-start returns it for retry.
  Receipt identity and the authoritative reread are separate durable facts too:
  neither alone confirms.

  The resource carries no domain of its own. It is registered with the existing
  Staking and Redemption domains, and every call names the owning one, so no
  implicit domain can add eager authority a transition has not proven.
  """

  use Ash.Resource,
    domain: nil,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @capabilities [:stake, :redeem]
  @states [
    :prepared,
    :approval_dispatched,
    :approval_submitted,
    :approval_verified,
    :action_dispatched,
    :action_submitted,
    :confirmed,
    :reverted,
    :not_sent,
    :cancelled
  ]

  # The two states from which the action phase may be claimed: an action that
  # needs no approval, and one whose approval receipt and allowance both hold.
  @action_claimable [:prepared, :approval_verified]

  # A review may be withdrawn before either dispatch is claimed, or once the
  # approval is fully verified while the action dispatch is still unclaimed.
  # A hashless claimed phase and a submitted-but-unverified approval stay open:
  # a transaction that may yet land is never closed as though it had not.
  @withdrawable [:prepared, :approval_verified]

  postgres do
    table "stake_redeem_operations"
    repo(AshPlatform.Repo)

    references do
      reference(:human_account, on_delete: :restrict)
    end

    identity_wheres_to_sql(one_active_per_capability: "terminal_at IS NULL")
  end

  attributes do
    uuid_primary_key :id

    # Never accepted by an update: the prepared identity is the operation.
    attribute :action_id, :string,
      allow_nil?: false,
      constraints: [min_length: 64, max_length: 64]

    attribute :capability, :atom, allow_nil?: false, constraints: [one_of: @capabilities]
    attribute :action, :string, allow_nil?: false, constraints: [max_length: 40]
    attribute :envelope, :map, allow_nil?: false, sensitive?: true
    attribute :state, :atom, allow_nil?: false, default: :prepared, constraints: [one_of: @states]

    attribute :approval_dispatched_at, :utc_datetime_usec

    attribute :approval_transaction_hash, :string,
      sensitive?: true,
      constraints: [min_length: 66, max_length: 66]

    attribute :approval_receipt_at, :utc_datetime_usec
    attribute :approval_reread_at, :utc_datetime_usec

    attribute :action_dispatched_at, :utc_datetime_usec

    attribute :action_transaction_hash, :string,
      sensitive?: true,
      constraints: [min_length: 66, max_length: 66]

    attribute :action_receipt_at, :utc_datetime_usec
    attribute :action_reread_at, :utc_datetime_usec

    attribute :reason, :string, constraints: [max_length: 120]
    attribute :terminal_at, :utc_datetime_usec
    timestamps()
  end

  relationships do
    belongs_to :human_account, AshPlatform.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end
  end

  identities do
    identity :unique_action_id, [:action_id]
    identity :unique_approval_transaction_hash, [:approval_transaction_hash]
    identity :unique_action_transaction_hash, [:action_transaction_hash]

    identity :one_active_per_capability, [:human_account_id, :capability] do
      where expr(is_nil(terminal_at))
    end
  end

  actions do
    # The primary read is what a locked reread resolves the row through.
    defaults [:read]

    read :active do
      get? true
      argument :human_account_id, :integer, allow_nil?: false
      argument :capability, :atom, allow_nil?: false

      filter expr(
               human_account_id == ^arg(:human_account_id) and
                 capability == ^arg(:capability) and is_nil(terminal_at)
             )
    end

    create :prepare do
      accept [:action_id, :capability, :action, :envelope]
      argument :human_account_id, :integer, allow_nil?: false
      change set_attribute(:human_account_id, arg(:human_account_id))
    end

    update :claim_approval_dispatch do
      accept []
      require_atomic? false
      validate attribute_equals(:state, :prepared)
      change set_attribute(:approval_dispatched_at, &DateTime.utc_now/0)
      change set_attribute(:state, :approval_dispatched)
    end

    update :bind_approval_hash do
      accept [:approval_transaction_hash]
      require_atomic? false
      validate attribute_equals(:state, :approval_dispatched)
      validate present(:approval_transaction_hash)
      change set_attribute(:state, :approval_submitted)
    end

    update :record_approval_receipt do
      accept []
      require_atomic? false
      validate attribute_equals(:state, :approval_submitted)
      change set_attribute(:approval_receipt_at, &DateTime.utc_now/0)
    end

    # The exact approval receipt plus the exact allowance reread. Receipt-only
    # approval never reaches here, so it never enables the action phase.
    update :verify_approval do
      accept []
      require_atomic? false
      validate attribute_equals(:state, :approval_submitted)
      validate present(:approval_receipt_at)
      change set_attribute(:approval_reread_at, &DateTime.utc_now/0)
      change set_attribute(:state, :approval_verified)
    end

    update :claim_action_dispatch do
      accept []
      require_atomic? false
      validate attribute_in(:state, @action_claimable)
      change set_attribute(:action_dispatched_at, &DateTime.utc_now/0)
      change set_attribute(:state, :action_dispatched)
    end

    update :bind_action_hash do
      accept [:action_transaction_hash]
      require_atomic? false
      validate attribute_equals(:state, :action_dispatched)
      validate present(:action_transaction_hash)
      change set_attribute(:state, :action_submitted)
    end

    update :record_action_receipt do
      accept []
      require_atomic? false
      validate attribute_equals(:state, :action_submitted)
      change set_attribute(:action_receipt_at, &DateTime.utc_now/0)
    end

    update :confirm do
      accept []
      require_atomic? false
      validate attribute_equals(:state, :action_submitted)
      validate present(:action_receipt_at)
      change set_attribute(:action_reread_at, &DateTime.utc_now/0)
      change set_attribute(:state, :confirmed)
      change set_attribute(:terminal_at, &DateTime.utc_now/0)
    end

    update :record_action_revert do
      accept [:reason]
      require_atomic? false
      validate attribute_equals(:state, :action_submitted)
      change set_attribute(:action_receipt_at, &DateTime.utc_now/0)
      change set_attribute(:state, :reverted)
      change set_attribute(:terminal_at, &DateTime.utc_now/0)
    end

    update :record_approval_revert do
      accept [:reason]
      require_atomic? false
      validate attribute_equals(:state, :approval_submitted)
      change set_attribute(:approval_receipt_at, &DateTime.utc_now/0)
      change set_attribute(:state, :reverted)
      change set_attribute(:terminal_at, &DateTime.utc_now/0)
    end

    update :cancel do
      accept [:reason]
      require_atomic? false
      validate attribute_in(:state, @withdrawable)
      change set_attribute(:state, :cancelled)
      change set_attribute(:terminal_at, &DateTime.utc_now/0)
    end

    # The terminal exit for a transaction-send request the wallet explicitly
    # rejected with EIP-1193 4001. Pre-send failures use the retry actions below;
    # timeouts, reloads and other failures after send begins remain uncertain.
    update :close_not_sent do
      accept [:reason]
      require_atomic? false
      validate attribute_in(:state, [:approval_dispatched, :action_dispatched])
      change set_attribute(:state, :not_sent)
      change set_attribute(:terminal_at, &DateTime.utc_now/0)
    end

    # The browser proved the claimed phase never reached its wallet send, so the
    # review becomes signable again instead of ending. Each release clears only
    # its own dispatch timestamp and keeps every approval fact. If a hash bound
    # first, the state is already submitted and these validations refuse it.
    update :release_unstarted_approval do
      accept []
      require_atomic? false
      validate attribute_equals(:state, :approval_dispatched)
      change set_attribute(:approval_dispatched_at, nil)
      change set_attribute(:state, :prepared)
    end

    update :release_unstarted_action do
      accept []
      require_atomic? false
      validate attribute_equals(:state, :action_dispatched)
      change set_attribute(:action_dispatched_at, nil)
      change set_attribute(:state, :prepared)
    end

    # Reachable only after the approval receipt and the exact allowance both
    # held, so the stake is never asked to approve a second time.
    update :release_unstarted_action_after_approval do
      accept []
      require_atomic? false
      validate attribute_equals(:state, :action_dispatched)
      change set_attribute(:action_dispatched_at, nil)
      change set_attribute(:state, :approval_verified)
    end
  end

  policies do
    policy always() do
      authorize_if AshPlatform.Checks.SystemActor
    end
  end
end
