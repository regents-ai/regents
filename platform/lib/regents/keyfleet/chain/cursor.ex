defmodule Regents.Keyfleet.Chain.Cursor do
  @moduledoc """
  How far one fleet's key history has been read from the chain, and whether it
  can be trusted right now.

  Base makes five blocks a second from Denim (5 November 2026, 18:00 UTC;
  one every two seconds before it), and nothing here waits for more: ownership is recorded at the head.

  It also numbers the fleet's proposal and budget records (`proposal_seq`),
  its key reveals and ended draw waits (`reveal_seq`), its ownership epochs
  (`ownership_seq`) and its shards issued and ended (`shard_seq`).
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Chain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  # Ownership is fresh while the head was read within this many seconds (one
  # five-minute turn of `Regents.Keyfleet.Chain.ReadFleet` and two retries a minute
  # apart), and the record reaches to within this many blocks of it (ten
  # minutes of Base at five blocks a second).
  @fresh_seconds 420
  @fresh_blocks 3_000

  postgres do
    table "chain_cursors"
    schema("keyfleet_app")
    repo(Regents.Repo)

    check_constraints do
      for field <- [
            :next_block,
            :head_block,
            :proposal_seq,
            :reveal_seq,
            :ownership_seq,
            :shard_seq
          ] do
        check_constraint(field, "chain_cursors_nonnegative_#{field}", check: "#{field} >= 0")
      end

      check_constraint(:head_block_hash, "chain_cursors_head_hash_shape",
        check: "head_block_hash ~ '^0x[0-9a-f]{64}$'"
      )
    end
  end

  actions do
    defaults [:read]

    read :fresh do
      argument :fleet_id, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and fresh?)
      get? true
    end

    # Starts reading a fleet at its deployment block; an existing cursor is
    # returned untouched.
    create :open do
      public? false
      accept [:fleet_id, :next_block]
      upsert? true
      upsert_fields []
      upsert_condition expr(false)
      return_skipped_upsert? true
    end

    # The fleet's cursor while it still stands at `next_block`. A pass writes
    # the cursor only through this, so it never undoes another pass's progress.
    read :standing do
      argument :fleet_id, :string, allow_nil?: false
      argument :next_block, :integer, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and next_block == ^arg(:next_block))
    end

    update :advance do
      public? false
      accept [:next_block, :head_block, :head_block_hash, :observed_at]
      require_attributes [:next_block, :head_block, :head_block_hash, :observed_at]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action([:open, :advance]) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    # The first block not yet read.
    attribute :next_block, :integer, allow_nil?: false, public?: true, constraints: [min: 0]

    attribute :head_block, :integer, public?: true, constraints: [min: 0]

    attribute :head_block_hash, :string,
      public?: true,
      constraints: [match: ~r/\A0x[0-9a-f]{64}\z/, trim?: false]

    # When the head was last read.
    attribute :observed_at, :utc_datetime_usec, public?: true

    # The last number given to one of the fleet's proposal, vote, execution,
    # launch, receipt or payment records. It is moved only by `Regents.Keyfleet.Chain.take_proposal_seq!/1`.
    attribute :proposal_seq, :integer,
      allow_nil?: false,
      default: 0,
      public?: true,
      constraints: [min: 0]

    # The last number given to one of the fleet's key reveals or ended draw
    # waits. It is moved only by `Regents.Keyfleet.Chain.take_reveal_seq!/1`.
    attribute :reveal_seq, :integer,
      allow_nil?: false,
      default: 0,
      public?: true,
      constraints: [min: 0]

    # The last number given to one of the fleet's ownership epochs. It is moved
    # only by `Regents.Keyfleet.Chain.take_ownership_seq!/1`.
    attribute :ownership_seq, :integer,
      allow_nil?: false,
      default: 0,
      public?: true,
      constraints: [min: 0]

    # The last number given to one of the fleet's shards issued or ended. It is
    # moved only by `Regents.Keyfleet.Chain.take_shard_seq!/1`.
    attribute :shard_seq, :integer,
      allow_nil?: false,
      default: 0,
      public?: true,
      constraints: [min: 0]
  end

  relationships do
    belongs_to :fleet, Regents.Keyfleet.Fleets.Fleet do
      attribute_type :string
      primary_key? true
      allow_nil? false
      public? true
    end
  end

  calculations do
    calculate :fresh?,
              :boolean,
              expr(
                not is_nil(observed_at) and observed_at > ago(@fresh_seconds, :second) and
                  head_block - next_block < @fresh_blocks
              )
  end
end
