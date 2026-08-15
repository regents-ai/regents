defmodule AshPlatform.Staking.Snapshot do
  @moduledoc "Onchain REGENT staking reads and user-signed action preparation."

  use Ash.Resource,
    domain: AshPlatform.Staking,
    authorizers: [Ash.Policy.Authorizer]

  alias AshPlatform.Staking.Actions

  actions do
    action :overview, :map do
      run fn input, context -> Actions.overview(input, context) end
    end

    action :account, :map do
      run fn input, context -> Actions.account(input, context) end
    end

    action :prepare_stake, :map do
      argument :expected_signer, :string, allow_nil?: false
      argument :amount, :string, allow_nil?: false
      run fn input, context -> Actions.prepare("stake", input, context) end
    end

    action :prepare_unstake, :map do
      argument :expected_signer, :string, allow_nil?: false
      argument :amount, :string, allow_nil?: false
      run fn input, context -> Actions.prepare("unstake", input, context) end
    end

    action :prepare_claim_usdc, :map do
      argument :expected_signer, :string, allow_nil?: false
      run fn input, context -> Actions.prepare("claim_usdc", input, context) end
    end

    action :prepare_claim_regent, :map do
      argument :expected_signer, :string, allow_nil?: false
      run fn input, context -> Actions.prepare("claim_regent", input, context) end
    end

    action :prepare_claim_and_restake_regent, :map do
      argument :expected_signer, :string, allow_nil?: false
      run fn input, context -> Actions.prepare("claim_and_restake_regent", input, context) end
    end

    action :confirm_wallet_action, :map do
      argument :envelope, :map, allow_nil?: false
      argument :transaction_hash, :string, allow_nil?: false
      argument :approval_transaction_hash, :string
      run fn input, context -> Actions.confirm(input, context) end
    end

    action :restore_submitted_action, :map do
      argument :envelope, :map, allow_nil?: false
      run fn input, context -> Actions.restore(input, context) end
    end

    action :verify_approval_submission, :atom do
      constraints one_of: [:success, :reverted, :pending]
      argument :envelope, :map, allow_nil?: false
      argument :transaction_hash, :string, allow_nil?: false
      run fn input, context -> Actions.approval_status(input, context) end
    end

    action :claim_wallet_dispatch, :map do
      argument :action_id, :string, allow_nil?: false
      argument :phase, :atom, allow_nil?: false, constraints: [one_of: [:approval, :action]]
      run fn input, context -> Actions.claim_dispatch(input, context) end
    end

    action :bind_submitted_hash, :map do
      argument :action_id, :string, allow_nil?: false
      argument :phase, :atom, allow_nil?: false, constraints: [one_of: [:approval, :action]]
      argument :transaction_hash, :string, allow_nil?: false
      run fn input, context -> Actions.bind_hash(input, context) end
    end

    action :close_not_sent, :map do
      argument :action_id, :string, allow_nil?: false
      argument :phase, :atom, allow_nil?: false, constraints: [one_of: [:approval, :action]]
      run fn input, context -> Actions.close_not_sent(input, context) end
    end

    action :cancel_operation, :map do
      argument :action_id, :string, allow_nil?: false
      run fn input, context -> Actions.cancel_operation(input, context) end
    end

    action :active_operation, :map do
      run fn input, context -> Actions.active_operation(input, context) end
    end
  end

  policies do
    policy action(:overview) do
      authorize_if always()
    end

    policy action([
             :account,
             :prepare_stake,
             :prepare_unstake,
             :prepare_claim_usdc,
             :prepare_claim_regent,
             :prepare_claim_and_restake_regent,
             :confirm_wallet_action,
             :restore_submitted_action,
             :verify_approval_submission,
             :claim_wallet_dispatch,
             :bind_submitted_hash,
             :close_not_sent,
             :cancel_operation,
             :active_operation
           ]) do
      authorize_if AshPlatform.Staking.Checks.HumanActor
    end
  end
end
