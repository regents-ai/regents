defmodule Regents.Keyfleet.Treasury.Reading do
  @moduledoc """
  A fleet's money as its contracts held it at one block: what its treasury
  holds and its reward ledger backs of each asset the daily split shares,
  the split's rate, when it last ran and when anyone may next run it, the
  launch token once bound, the Cascade completion reserve, the protocol
  share owed, the USDC from Key sales waiting to turn into REGENT, and since
  when each of those two has been waiting.

  `Regents.Keyfleet.Chain.TreasuryReader` reads them every five minutes at the
  head's block and keeps only the latest reading of each fleet: a reading of
  the block kept, or of an earlier one, is ignored, and comes back marked
  `upsert_skipped` in its metadata.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Treasury,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @max_bigint 9_223_372_036_854_775_807

  postgres do
    table "treasury_readings"
    schema("keyfleet_app")
    repo(Regents.Repo)
    migration_defaults(conversion_waiting: "0")

    check_constraints do
      check_constraint(:block_hash, "treasury_readings_block_hash_shape",
        check: "block_hash ~ '^0x[0-9a-f]{64}$'"
      )

      for field <- [:block_number, :cascade_reserve, :protocol_share_owed, :conversion_waiting] do
        check_constraint(field, "treasury_readings_nonnegative_#{field}", check: "#{field} >= 0")
      end

      check_constraint(:daily_split_bps, "treasury_readings_daily_split_bps_range",
        check: "daily_split_bps BETWEEN 0 AND 10000"
      )

      check_constraint(:launch_token, "treasury_readings_launch_token_shape",
        check: "launch_token ~ '^0x[0-9a-f]{40}$'"
      )
    end
  end

  actions do
    defaults [:read]

    create :record do
      public? false

      accept [
        :fleet_id,
        :block_number,
        :block_hash,
        :block_time,
        :cascade_reserve,
        :protocol_share_owed,
        :daily_split_bps,
        :last_run_at,
        :next_run_at,
        :launch_token,
        :assets,
        :protocol_share_owed_since,
        :conversion_waiting,
        :conversion_waiting_since
      ]

      upsert? true
      upsert_identity :unique_fleet

      upsert_fields [
        :block_number,
        :block_hash,
        :block_time,
        :cascade_reserve,
        :protocol_share_owed,
        :daily_split_bps,
        :last_run_at,
        :next_run_at,
        :launch_token,
        :assets,
        :protocol_share_owed_since,
        :conversion_waiting,
        :conversion_waiting_since
      ]

      upsert_condition expr(upsert_conflict(:block_number) > block_number)
      return_skipped_upsert? true
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:record) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    uuid_primary_key :id

    # The block read, and its time on the chain.
    attribute :block_number, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 0, max: @max_bigint]

    attribute :block_hash, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/\A0x[0-9a-f]{64}\z/, trim?: false]

    attribute :block_time, :utc_datetime_usec, allow_nil?: false, public?: true

    # USDC, in atomic units: held back for the next Cascade level, and owed to
    # REGENT staking.
    for field <- [:cascade_reserve, :protocol_share_owed] do
      attribute field, :decimal, allow_nil?: false, public?: true, constraints: [min: 0]
    end

    # USDC from Key sales waiting to turn into REGENT, in atomic units.
    attribute :conversion_waiting, :decimal,
      allow_nil?: false,
      public?: true,
      constraints: [min: 0]

    # By the chain's clock: since when the protocol share has been owed, and
    # since when USDC has been waiting to turn into REGENT, each without
    # dropping to nothing at any block read; nil while nothing is.
    attribute :protocol_share_owed_since, :utc_datetime_usec, public?: true
    attribute :conversion_waiting_since, :utc_datetime_usec, public?: true

    # The daily split's rate, in basis points of each asset's balance; when
    # it last ran, nil before its first run; and when anyone may next run it,
    # nil while no key has been sold.
    attribute :daily_split_bps, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 0, max: 10_000]

    attribute :last_run_at, :utc_datetime, public?: true
    attribute :next_run_at, :utc_datetime, public?: true

    # The fleet's own launched token once bound to the split, and nil until
    # then.
    attribute :launch_token, :string,
      public?: true,
      constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]

    # Each asset the daily split shares, in the order it splits them: ETH,
    # REGENT, USDC, then OUSD once admitted, then the launch token once bound.
    attribute :assets, {:array, Regents.Keyfleet.Treasury.AssetBalance},
      allow_nil?: false,
      public?: true
  end

  relationships do
    belongs_to :fleet, Regents.Keyfleet.Fleets.Fleet do
      attribute_type :string
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_fleet, [:fleet_id]
  end
end
