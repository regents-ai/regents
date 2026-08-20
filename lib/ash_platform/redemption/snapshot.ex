defmodule AshPlatform.Redemption.Snapshot do
  @moduledoc "Onchain Animata redemption reads and user-signed action preparation."

  use Ash.Resource,
    domain: AshPlatform.Redemption,
    authorizers: [Ash.Policy.Authorizer]

  alias AshPlatform.Redemption.Actions

  actions do
    action :overview, :map do
      run fn input, context -> Actions.overview(input, context) end
    end

    action :account_for_wallet, :map do
      argument :expected_signer, :string, allow_nil?: false
      argument :collection, :string
      argument :token_id, :integer, constraints: [min: 1, max: 999]
      run fn input, context -> Actions.account_for_wallet(input, context) end
    end

    action :prepare_nft_approval, :map do
      argument :expected_signer, :string, allow_nil?: false
      argument :collection, :string, allow_nil?: false
      run fn input, context -> Actions.prepare("approve_nft_collection", input, context) end
    end

    action :prepare_usdc_approval, :map do
      argument :expected_signer, :string, allow_nil?: false
      run fn input, context -> Actions.prepare("approve_exact_usdc", input, context) end
    end

    action :prepare_redeem, :map do
      argument :expected_signer, :string, allow_nil?: false
      argument :collection, :string, allow_nil?: false
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: 999]
      run fn input, context -> Actions.prepare("redeem", input, context) end
    end

    action :prepare_claim, :map do
      argument :expected_signer, :string, allow_nil?: false
      run fn input, context -> Actions.prepare("claim", input, context) end
    end

    action :confirm_wallet_action, :map do
      argument :envelope, :map, allow_nil?: false
      argument :transaction_hash, :string, allow_nil?: false
      run fn input, context -> Actions.confirm(input, context) end
    end

    action :restore_submitted_action, :map do
      argument :envelope, :map, allow_nil?: false
      run fn input, context -> Actions.restore(input, context) end
    end

    action :claim_wallet_dispatch, :map do
      argument :envelope, :map, allow_nil?: false
      run fn input, context -> Actions.claim_dispatch(input, context) end
    end

    action :bind_submitted_hash, :map do
      argument :action_id, :string, allow_nil?: false
      argument :transaction_hash, :string, allow_nil?: false
      run fn input, context -> Actions.bind_hash(input, context) end
    end

    action :close_not_sent, :map do
      argument :action_id, :string, allow_nil?: false
      run fn input, context -> Actions.close_not_sent(input, context) end
    end

    action :release_unstarted_dispatch, :map do
      argument :action_id, :string, allow_nil?: false
      run fn input, context -> Actions.release_unstarted(input, context) end
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
             :account_for_wallet,
             :prepare_nft_approval,
             :prepare_usdc_approval,
             :prepare_redeem,
             :prepare_claim,
             :confirm_wallet_action,
             :restore_submitted_action,
             :claim_wallet_dispatch,
             :bind_submitted_hash,
             :close_not_sent,
             :release_unstarted_dispatch,
             :cancel_operation,
             :active_operation
           ]) do
      authorize_if AshPlatform.Redemption.Checks.HumanActor
    end
  end
end
