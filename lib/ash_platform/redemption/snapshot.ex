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
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: 999]
      run fn input, context -> Actions.prepare("approve_nft_collection", input, context) end
    end

    action :prepare_usdc_approval, :map do
      argument :expected_signer, :string, allow_nil?: false
      argument :collection, :string, allow_nil?: false
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: 999]
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
             :prepare_claim
           ]) do
      authorize_if AshPlatform.Redemption.Checks.HumanActor
    end
  end
end
