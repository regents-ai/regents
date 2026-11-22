defmodule Regents.Autolaunch.TokenStake do
  @moduledoc """
  Stakes of a launched token in its launch's splitter, one row per `Staked`
  log, read in the same pass and under the same cursor as the token's trades.
  The staker is the wallet the log names, the one that called `stake`; the
  amount is in the token's raw units.

  A row is written once and never changed or removed: reading the same log
  again, or rebuilding the token's trades after the chain changed, keeps the
  row as first saved, and a stake the chain later took back stays saved.
  Unstaking is not recorded, and a `Staked` log of nothing is not saved.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """
  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @address ~r/\A0x[0-9a-f]{40}\z/
  @hash ~r/\A0x[0-9a-f]{64}\z/

  postgres do
    table "token_stakes"
    schema("autolaunch_app")
    repo(Regents.Repo)
  end

  attributes do
    uuid_primary_key :id
    attribute :chain_id, :integer, allow_nil?: false, constraints: [min: 1]
    # The launch's splitter, where the token is staked.
    attribute :splitter, :string, allow_nil?: false, constraints: [match: @address]
    attribute :staker, :string, allow_nil?: false, constraints: [match: @address]
    # Raw token units, exactly as the log carried them.
    attribute :amount, :decimal, allow_nil?: false, constraints: [greater_than: 0]
    attribute :transaction_hash, :string, allow_nil?: false, constraints: [match: @hash]
    attribute :log_index, :integer, allow_nil?: false, constraints: [min: 0]
    attribute :block_number, :integer, allow_nil?: false, constraints: [min: 0]
    attribute :block_hash, :string, allow_nil?: false, constraints: [match: @hash]
    attribute :occurred_at, :utc_datetime_usec, allow_nil?: false
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :token, Regents.Autolaunch.Token do
      allow_nil? false
    end
  end

  identities do
    identity :chain_log, [:chain_id, :transaction_hash, :log_index]
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
