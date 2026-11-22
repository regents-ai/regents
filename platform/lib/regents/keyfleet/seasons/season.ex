defmodule Regents.Keyfleet.Seasons.Season do
  @moduledoc """
  One three-hour season of a fleet: its number, when it starts and ends, what
  the fleet holds through it and the Key that is captain, if any.

  A season is opened for picks three hours before it starts, locked at its
  start, when its holding, captain and the holding's open price are set, and
  settled at its end, when the holding's close price and its own result over
  the season are set. Only `Regents.Keyfleet.Seasons.Turn` writes seasons. A fleet has
  at most one season taking picks and one running at a time, and seasons are
  never removed. Only the fleet's members read them, but for the season
  under way, which anyone reads with how many Keys picked for it
  (`:running`), and a settled season: that is public record, read by anyone
  (`:settled`), its picks a page at a time.

  Opening one, which ends every turn, is announced on `Regents.Keyfleet.Seasons.topic/1`
  as "seasons_changed".
  """
  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Keyfleet.Seasons,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  @bigint 9_223_372_036_854_775_807

  postgres do
    table "seasons"
    schema("keyfleet_app")
    repo(Regents.Repo)

    check_constraints do
      check_constraint(:number, "seasons_number", check: "number > 0")

      check_constraint(:ends_at, "seasons_three_hours",
        check: "ends_at = starts_at + interval '3 hours'"
      )

      check_constraint(:starts_at, "seasons_boundary",
        check:
          "date_trunc('hour', starts_at) = starts_at AND extract(hour FROM starts_at)::integer % 3 = 0"
      )

      check_constraint(:holding, "seasons_holding_shape",
        check: "holding = 'USDC' OR holding ~ '^[A-Z0-9]+-USD$'"
      )

      check_constraint(:captain_key, "seasons_captain_key", check: "captain_key > 0")

      check_constraint(:holding_open_price, "seasons_prices",
        check: "holding_open_price > 0 AND holding_close_price > 0"
      )

      check_constraint(:locked_at, "seasons_locked",
        check:
          "(holding IS NULL) = (locked_at IS NULL) AND " <>
            "(locked_at IS NOT NULL OR (captain_key IS NULL AND holding_open_price IS NULL))"
      )

      check_constraint(:settled_at, "seasons_settled",
        check:
          "(settled_at IS NULL OR locked_at IS NOT NULL) AND " <>
            "(settled_at IS NOT NULL OR holding_close_price IS NULL)"
      )

      check_constraint(:holding_result, "seasons_result",
        check:
          "(holding_result IS NOT NULL) = " <>
            "(settled_at IS NOT NULL AND holding_open_price IS NOT NULL AND holding_close_price IS NOT NULL)"
      )
    end

    custom_indexes do
      index(["fleet_id"],
        name: "seasons_taking_picks_index",
        unique: true,
        where: "locked_at IS NULL"
      )

      index(["fleet_id"],
        name: "seasons_running_index",
        unique: true,
        where: "locked_at IS NOT NULL AND settled_at IS NULL"
      )
    end
  end

  actions do
    # Only for the turn, and for filters that follow a pick to its season.
    read :read do
      primary? true
      public? false
    end

    # The fleet's latest hundred seasons, newest first.
    read :in_fleet do
      argument :fleet_id, :string, allow_nil?: false

      validate Regents.Keyfleet.Graph.Validations.KnownFleet
      filter expr(fleet_id == ^arg(:fleet_id))
      prepare build(sort: [number: :desc], limit: 100)
    end

    read :numbered do
      argument :fleet_id, :string, allow_nil?: false
      argument :number, :integer, allow_nil?: false
      get? true

      filter expr(fleet_id == ^arg(:fleet_id) and number == ^arg(:number))
    end

    # The season the fleet's members pick for now, until its turn locks it,
    # with how many Keys have locked a pick for it, never whose or what.
    read :upcoming do
      argument :fleet_id, :string, allow_nil?: false
      get? true

      filter expr(fleet_id == ^arg(:fleet_id) and is_nil(locked_at))
      prepare build(load: [:keys_locked])
    end

    # The season under way: locked at its start, not yet settled, with how
    # many Keys picked for it.
    read :running do
      argument :fleet_id, :string, allow_nil?: false
      get? true

      filter expr(fleet_id == ^arg(:fleet_id) and not is_nil(locked_at) and is_nil(settled_at))
      prepare build(load: [:keys_locked])
    end

    # The fleet's settled seasons, newest first, below `before` when it is
    # given, or the one numbered `number`, each with how many Keys picked and
    # its best pick: the fleet's public record. A season's picks are read a
    # page at a time (`Regents.Keyfleet.Seasons.SeasonPick`, `:in_settled_season`).
    read :settled do
      argument :fleet_id, :string, allow_nil?: false
      argument :before, :integer, constraints: [min: 1, max: @bigint]
      argument :number, :integer, constraints: [min: 1, max: @bigint]

      filter expr(
               fleet_id == ^arg(:fleet_id) and not is_nil(settled_at) and
                 (is_nil(^arg(:before)) or number < ^arg(:before)) and
                 (is_nil(^arg(:number)) or number == ^arg(:number))
             )

      prepare build(sort: [number: :desc], load: [:keys_locked, :best_pick])
    end

    create :open do
      accept [:fleet_id, :number, :starts_at]
      change Regents.Keyfleet.Seasons.Changes.SeasonEnd
    end

    update :lock do
      accept [:holding, :captain_key, :holding_open_price]
      change set_attribute(:locked_at, &DateTime.utc_now/0)
    end

    update :settle do
      accept [:holding_close_price, :holding_result]
      change set_attribute(:settled_at, &DateTime.utc_now/0)
    end
  end

  policies do
    # Only for the turn, and for filters that follow a pick to its season.
    policy action(:read) do
      authorize_if always()
    end

    policy action([:in_fleet, :numbered, :upcoming]) do
      authorize_if {Regents.Keyfleet.Access.Check, read: :seasons, scope: :fleet_id}
      authorize_if actor_attribute_equals(:role, :system)
    end

    # Wider than the class: a settled season is public record, and so is the
    # season under way, whose holding and captain follow from the record of
    # the one settled as it started. Its picks stay the members'
    # (`Regents.Keyfleet.Seasons.SeasonPick`, `:in_season`).
    policy action([:running, :settled]) do
      authorize_if always()
    end

    policy action([:open, :lock, :settle]) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :number, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1, max: @bigint]

    attribute :starts_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :ends_at, :utc_datetime_usec, allow_nil?: false, public?: true, writable?: false

    # A Coinbase product quoted in US dollars, or USDC; set when the season starts.
    attribute :holding, :string,
      public?: true,
      constraints: [match: ~r/\A(USDC|[A-Z0-9]+-USD)\z/, trim?: false, max_length: 32]

    # The Key whose pick made the holding, if one did.
    attribute :captain_key, :integer, public?: true, constraints: [min: 1, max: @bigint]

    # The holding's price at the season's start and end, as Coinbase sent
    # them, and its result over the season: nil when either is unknown.
    attribute :holding_open_price, :decimal, public?: true
    attribute :holding_close_price, :decimal, public?: true
    attribute :holding_result, :decimal, public?: true

    attribute :locked_at, :utc_datetime_usec, public?: true, writable?: false
    attribute :settled_at, :utc_datetime_usec, public?: true, writable?: false

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :fleet, Regents.Keyfleet.Fleets.Fleet do
      attribute_type :string
      attribute_writable? true
      allow_nil? false
      public? true
    end

    has_many :picks, Regents.Keyfleet.Seasons.SeasonPick

    # A settled season's best pick, as its public record shows it: the
    # highest result, and of equal results the one locked first. It orders
    # picks by the result kept, to 28 digits, as `Regents.Keyfleet.Seasons.Rules.best/1`,
    # which decides the crown exactly, orders any two whose results still
    # differ when kept so.
    has_one :best_pick, Regents.Keyfleet.Seasons.SeasonPick do
      public? true
      from_many? true
      read_action :settled
      filter expr(not is_nil(result))
      sort result: :desc, lock_order: :asc
    end
  end

  aggregates do
    # How many Keys have locked a pick for the season: whoever reads the
    # season counts them without reading whose or what they are.
    count :keys_locked, :picks do
      public? true
      authorize? false
    end
  end

  identities do
    identity :numbered, [:fleet_id, :number]
    identity :starting, [:fleet_id, :starts_at]
  end

  pub_sub do
    module Phoenix.PubSub
    name Regents.PubSub
    prefix "keyfleet"
    broadcast_type :phoenix_broadcast

    publish :open, ["seasons", :fleet_id],
      event: "seasons_changed",
      transform: fn _notification -> %{} end
  end
end
