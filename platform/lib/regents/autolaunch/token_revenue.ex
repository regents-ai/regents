defmodule Regents.Autolaunch.TokenRevenue do
  @moduledoc """
  Revenue a Revstake token's splitter recognized, one row per
  `RevenueRecognized` log, read in the same pass and under the same cursor as
  the token's trades. The amount is the gross the splitter took in, in its own
  asset (USDC, REGENT or the launch token); the stakers' share is the part that
  went to stakers.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """
  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "token_revenues"
    schema("autolaunch_app")
    repo(Regents.Repo)

    custom_indexes do
      index([:token_id, :block_number])
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :transaction_hash, :string, allow_nil?: false
    attribute :block_hash, :string, allow_nil?: false
    attribute :block_number, :integer, allow_nil?: false
    attribute :log_index, :integer, allow_nil?: false
    attribute :occurred_at, :utc_datetime_usec, allow_nil?: false
    # USDC, REGENT or the launch token's own symbol.
    attribute :asset_symbol, :string, allow_nil?: false
    attribute :amount, :decimal, allow_nil?: false, constraints: [min: 0]
    attribute :staker_share, :decimal, allow_nil?: false, constraints: [min: 0]
  end

  relationships do
    belongs_to :token, Regents.Autolaunch.Token do
      allow_nil? false
    end
  end

  identities do
    identity :splitter_log, [:token_id, :transaction_hash, :log_index]
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
