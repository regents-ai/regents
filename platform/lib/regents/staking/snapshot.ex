defmodule Regents.Staking.Snapshot do
  @moduledoc "Onchain REGENT staking reads."

  use Ash.Resource,
    domain: Regents.Staking,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Staking.Actions

  # Closures rather than captures: a capture evaluated inside the DSL would
  # make the implementation module a compile-time dependency of this resource.
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
  end

  policies do
    policy action([:overview, :account_for_wallet]) do
      authorize_if always()
    end

    policy action(:account) do
      authorize_if Regents.Staking.Checks.HumanActor
    end
  end
end
