defmodule RegentPoints.PeriodBonus do
  @moduledoc """
  One account's NFT bonus for one 30-day program period, written by the tally at the
  period's end with the tier held then. The tier never changes afterwards; an award
  or correction for the period moves its earned total and bonus at that tier.
  """
  use Ash.Resource,
    domain: RegentPoints,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    migrate?(Application.compile_env(:regent_points, :generate_migrations, false))
    table "period_bonuses"
    schema("regent_points")
    repo(&RegentPoints.repo/2)

    check_constraints do
      check_constraint(:bonus_percent, "period_bonus_tier",
        check: "bonus_percent IN (#{Enum.join(RegentPoints.Bonus.allowed_percentages(), ",")})"
      )

      check_constraint(:bonus_micro, "period_bonus_amount",
        check:
          "earned_micro >= 0 AND nft_count >= 0 AND bonus_micro = earned_micro * bonus_percent / 100"
      )
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :program_id, :string, allow_nil?: false
    attribute :account_id, :integer, allow_nil?: false
    attribute :period, :integer, allow_nil?: false, constraints: [min: 1]
    attribute :earned_micro, :integer, allow_nil?: false
    attribute :nft_count, :integer, allow_nil?: false
    attribute :nft_block, :integer, allow_nil?: false
    attribute :bonus_percent, :integer, allow_nil?: false
    attribute :bonus_micro, :integer, allow_nil?: false
    create_timestamp :tallied_at
  end

  relationships do
    belongs_to :snapshot, RegentPoints.PeriodSnapshot

    belongs_to :account, RegentPoints.Account,
      define_attribute?: false,
      source_attribute: :account_id,
      attribute_type: :integer
  end

  actions do
    read :read do
      primary? true
    end

    create :record do
      accept [
        :program_id,
        :account_id,
        :period,
        :snapshot_id,
        :earned_micro,
        :nft_count,
        :nft_block,
        :bonus_percent,
        :bonus_micro
      ]

      validate present(:snapshot_id)
      change RegentPoints.FollowBalance
    end

    update :follow do
      accept [:earned_micro, :bonus_micro]
      change RegentPoints.FollowBalance
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(account_id == ^actor(:human_account_id))
    end
  end

  identities do
    identity :account_period, [:program_id, :account_id, :period]
  end

  pub_sub do
    module RegentPoints.PubSub
    name :regent_points
    prefix "points"
    broadcast_type :broadcast
    transform fn _notification -> :points_changed end
    publish :record, [:account_id]
    publish :follow, [:account_id]
    # Any account's total moved: the site's shared board reads again.
    publish :record, ["board"]
    publish :follow, ["board"]
  end
end
