defmodule AshPlatform.Redemption.Snapshot do
  @moduledoc "Onchain Animata redemption reads."

  use Ash.Resource,
    domain: AshPlatform.Redemption,
    authorizers: [Ash.Policy.Authorizer]

  alias AshPlatform.Redemption.Actions

  # Closures rather than captures: a capture evaluated inside the DSL would
  # make the implementation module a compile-time dependency of this resource.
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
  end

  policies do
    policy action([:overview, :account_for_wallet]) do
      authorize_if always()
    end
  end
end
