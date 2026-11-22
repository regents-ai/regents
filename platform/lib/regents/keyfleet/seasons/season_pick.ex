defmodule Regents.Keyfleet.Seasons.SeasonPick do
  @moduledoc """
  A Key's one pick for a season: a Coinbase product quoted in US dollars, or
  `USDC`, and a short reason if it gives one, one line a person would type
  (`Regents.Keyfleet.Seasons.Validations.Reason`).

  A Key picks once a season, whichever of its agents sends it. A pick is the
  whole pick: its product and its reason, none when it gives none. Until the
  season starts the pick may change; a change takes a new place in the order
  picks were locked (`lock_order`, from a database sequence), and sending the
  same pick again writes nothing and keeps its place. Until the season starts only the Key's
  holder and its agents read the pick; from the start every member of the
  fleet reads every pick, and once the season is settled anyone does, as
  its public record (`:settled`). Picks are never removed.

  At the season's start its turn sets each pick's open price, or why it is
  void; at the end its close price and result over the season, or that it is
  void.

  Each pick locked or changed is announced on
  `Regents.Keyfleet.Seasons.season_topic/1` as "season_changed".
  """
  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Keyfleet.Seasons,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  @bigint 9_223_372_036_854_775_807

  postgres do
    table "season_picks"
    schema("keyfleet_app")
    repo(Regents.Repo)
    migration_types(lock_order: :bigserial)

    references do
      reference(:season, on_delete: :restrict)
    end

    check_constraints do
      check_constraint(:token_id, "season_picks_token_id", check: "token_id > 0")

      check_constraint(:wallet, "season_picks_wallet_shape", check: "wallet ~ '^0x[0-9a-f]{40}$'")

      check_constraint(:product, "season_picks_product_shape",
        check: "product = 'USDC' OR product ~ '^[A-Z0-9]+-USD$'"
      )

      check_constraint(:open_price, "season_picks_prices",
        check: "open_price > 0 AND close_price > 0"
      )

      check_constraint(:close_price, "season_picks_close_after_open",
        check: "close_price IS NULL OR open_price IS NOT NULL"
      )

      check_constraint(:result, "season_picks_result",
        check: "(result IS NOT NULL) = (open_price IS NOT NULL AND close_price IS NOT NULL)"
      )

      check_constraint(:void, "season_picks_void",
        check:
          "void IS NULL OR (void IN ('ineligible', 'no_open_price') AND open_price IS NULL) OR " <>
            "(void = 'no_close_price' AND open_price IS NOT NULL AND close_price IS NULL)"
      )
    end

    custom_indexes do
      index(["season_id", "lock_order"], name: "season_picks_order_index")
    end
  end

  actions do
    create :pick do
      change Regents.Keyfleet.Agents.Changes.RecordAuthority
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      accept [:product, :reason]
      transaction? true

      argument :fleet_id, :string, allow_nil?: false
      argument :number, :integer, allow_nil?: false, constraints: [min: 1]

      validate Regents.Keyfleet.Graph.Validations.KnownFleet
      validate Regents.Keyfleet.Seasons.Validations.Reason

      # The Key's pick in the season is replaced only by a different one, and
      # then takes the newest place in the order.
      upsert? true
      upsert_identity :one_per_key

      upsert_fields [
        :product,
        :reason,
        :wallet,
        :picked_at,
        :acting_agent_wallet,
        :beneficiary_privy_user_id,
        :agent_pairing_id
      ]

      upsert_condition expr(
                         product != upsert_conflict(:product) or
                           is_distinct_from(reason, upsert_conflict(:reason))
                       )

      return_skipped_upsert? true

      # A pick is the whole pick: one sent with no reason has none, so the
      # condition above alone decides whether it is a change.
      change set_attribute(:reason, nil, new?: true)

      change Regents.Keyfleet.Seasons.Changes.Pick

      # A first pick takes the sequence's next place as the column's default;
      # a change takes the next one again.
      change atomic_update(
               :lock_order,
               expr(fragment("nextval('keyfleet_app.season_picks_lock_order_seq'::regclass)"))
             )
    end

    # Only for the turn.
    read :read do
      primary? true
      public? false
    end

    # The actor's own Key's pick for a season of the fleet.
    read :mine do
      argument :fleet_id, :string, allow_nil?: false
      argument :number, :integer, allow_nil?: false
      get? true

      filter expr(season.fleet_id == ^arg(:fleet_id) and season.number == ^arg(:number))
      prepare Regents.Keyfleet.Seasons.Preparations.OwnPick
    end

    # The picks of a season that has started, in the order they were locked,
    # after the one locked at `after` when it is given.
    read :in_season do
      argument :fleet_id, :string, allow_nil?: false
      argument :number, :integer, allow_nil?: false
      argument :after, :integer, constraints: [min: 1, max: @bigint]

      filter expr(
               season.fleet_id == ^arg(:fleet_id) and season.number == ^arg(:number) and
                 not is_nil(season.locked_at) and
                 (is_nil(^arg(:after)) or lock_order > ^arg(:after))
             )

      prepare build(sort: [lock_order: :asc])
    end

    # The same of a settled season, for anyone: the public record's.
    read :in_settled_season do
      argument :fleet_id, :string, allow_nil?: false
      argument :number, :integer, allow_nil?: false
      argument :after, :integer, constraints: [min: 1, max: @bigint]

      filter expr(
               season.fleet_id == ^arg(:fleet_id) and season.number == ^arg(:number) and
                 not is_nil(season.settled_at) and
                 (is_nil(^arg(:after)) or lock_order > ^arg(:after))
             )

      prepare build(sort: [lock_order: :asc])
    end

    # The picks of settled seasons, the public record's.
    read :settled do
      filter expr(not is_nil(season.settled_at))
    end

    update :open do
      accept [:open_price, :void]
    end

    update :close do
      accept [:close_price, :result, :void]
    end
  end

  policies do
    policy action(:pick) do
      authorize_if {Regents.Keyfleet.Access.Check, write: :seasons, scope: :fleet_id}
    end

    # Narrower than the class: before its season starts a pick is read only
    # by its own Key (`:mine`), and `:in_season` answers only started seasons.
    policy action([:mine, :in_season]) do
      authorize_if {Regents.Keyfleet.Access.Check, read: :seasons, scope: :fleet_id}
    end

    # Wider than the class: a settled season's picks are public record.
    policy action([:settled, :in_settled_season]) do
      authorize_if always()
    end

    policy action([:read, :open, :close]) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    attribute :acting_agent_wallet, :string, writable?: false
    attribute :beneficiary_privy_user_id, :string, writable?: false, sensitive?: true
    attribute :agent_pairing_id, :uuid, writable?: false

    uuid_primary_key :id

    attribute :token_id, :integer,
      allow_nil?: false,
      public?: true,
      writable?: false,
      constraints: [min: 1, max: @bigint]

    attribute :wallet, :string,
      allow_nil?: false,
      public?: true,
      writable?: false,
      constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]

    attribute :product, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/\A(USDC|[A-Z0-9]+-USD)\z/, trim?: false, max_length: 32]

    # Trimmed, and none when empty; its rules are the pick's
    # (`Regents.Keyfleet.Seasons.Validations.Reason`).
    attribute :reason, :string, public?: true

    # Where the pick stands among the season's picks: lower was locked first.
    attribute :lock_order, :integer,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true,
      constraints: [min: 1, max: @bigint]

    attribute :picked_at, :utc_datetime_usec,
      allow_nil?: false,
      public?: true,
      writable?: false,
      default: &DateTime.utc_now/0

    # Its product's price at the season's start and end, as Coinbase sent
    # them, and its result over the season.
    attribute :open_price, :decimal, public?: true
    attribute :close_price, :decimal, public?: true
    attribute :result, :decimal, public?: true

    # Why it scores nothing: its product was not open to picks at the start,
    # or had no price at the start or at the end.
    attribute :void, :atom,
      public?: true,
      constraints: [one_of: [:ineligible, :no_open_price, :no_close_price]]
  end

  relationships do
    belongs_to :season, Regents.Keyfleet.Seasons.Season do
      allow_nil? false
      public? true
      attribute_writable? false
    end
  end

  identities do
    identity :one_per_key, [:season_id, :token_id]
  end

  pub_sub do
    module Phoenix.PubSub
    name Regents.PubSub
    prefix "keyfleet"
    broadcast_type :phoenix_broadcast

    publish :pick, ["season", :season_id],
      event: "season_changed",
      filter: &(!Ash.Resource.get_metadata(&1.data, :upsert_skipped)),
      transform: fn _notification -> %{} end
  end
end
