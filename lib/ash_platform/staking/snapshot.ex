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

    action :account_for_wallet, :map do
      argument :expected_signer, :string, allow_nil?: false
      run fn input, context -> Actions.account_for_wallet(input, context) end
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
  end

  policies do
    policy action([
             :overview,
             :account_for_wallet,
             :prepare_stake,
             :prepare_unstake,
             :prepare_claim_usdc,
             :prepare_claim_regent,
             :prepare_claim_and_restake_regent
           ]) do
      authorize_if always()
    end

    policy action(:account) do
      authorize_if AshPlatform.Staking.Checks.HumanActor
    end
  end
end
