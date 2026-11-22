defmodule Regents.Keyfleet.Polls.Poll do
  @moduledoc """
  One poll in a fleet: its question, its choices, the starter's notes, the
  Key that started it and when it closes.

  A poll stays open for the 1 to 60 minutes its starter chose, or until the
  starter ends it. It is never removed. Only the fleet's members read its
  polls (`Regents.Keyfleet.Access`, `:polls`). Each choice's count of votes is read
  once the poll has closed (`Regents.Keyfleet.Polls.Calculations.Totals`).

  Starting and ending one is announced on `Regents.Keyfleet.Polls.fleet_topic/1` as
  "polls_changed", and ending one on `Regents.Keyfleet.Polls.topic/1` as
  "poll_changed".
  """
  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Keyfleet.Polls,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  @bigint 9_223_372_036_854_775_807
  @plain_text ~r/\A[^\p{Cc}\p{Cf}\p{Zl}\p{Zp}]*\z/u

  postgres do
    table "polls"
    schema("keyfleet_app")
    repo(Regents.Repo)

    check_constraints do
      check_constraint(:started_by_key, "polls_started_by_key", check: "started_by_key > 0")

      check_constraint(:started_by_wallet, "polls_started_by_wallet_shape",
        check: "started_by_wallet ~ '^0x[0-9a-f]{40}$'"
      )

      check_constraint(:choices, "polls_choices_count",
        check: "cardinality(choices) BETWEEN 2 AND 10"
      )
    end

    custom_indexes do
      index(["fleet_id", "inserted_at"], name: "polls_fleet_index")
      index(["fleet_id", "started_by_key", "inserted_at"], name: "polls_starter_index")
    end
  end

  actions do
    create :start do
      change Regents.Keyfleet.Agents.Changes.RecordAuthority
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      accept [:question, :choices, :notes]
      transaction? true

      argument :fleet_id, :string, allow_nil?: false
      argument :minutes, :integer, allow_nil?: false, constraints: [min: 1, max: 60]

      validate Regents.Keyfleet.Graph.Validations.KnownFleet
      validate Regents.Keyfleet.Polls.Validations.DistinctChoices
      change set_attribute(:fleet_id, arg(:fleet_id))
      change Regents.Keyfleet.Polls.Changes.StartPoll
    end

    # Only for filters that follow a vote to its poll, and for locking a poll.
    read :read do
      primary? true
      public? false
    end

    # The fleet's latest hundred polls, newest first.
    read :listed do
      argument :fleet_id, :string, allow_nil?: false

      validate Regents.Keyfleet.Graph.Validations.KnownFleet
      filter expr(fleet_id == ^arg(:fleet_id))

      prepare build(
                sort: [inserted_at: :desc, id: :desc],
                limit: 100,
                load: [:votes_cast, :totals]
              )
    end

    # The fleet's polls started, or stopped as they were ended or closed,
    # from just past `before_at` and `before_id`, newest first, `limit` at
    # most. `keys` and `wallet` keep the polls started as those Keys or by
    # that wallet (`Regents.Keyfleet.Preparations.DoneBy`).
    for {action, time} <- [started_before: :inserted_at, stopped_before: :stopped_at] do
      read action do
        argument :fleet_id, :string, allow_nil?: false
        argument :before_at, :utc_datetime_usec, allow_nil?: false
        argument :before_id, :uuid
        argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: 200]
        argument :keys, {:array, :integer}
        argument :wallet, :string, constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]
        filter expr(fleet_id == ^arg(:fleet_id))

        prepare {Regents.Keyfleet.Preparations.NewestFirst,
                 sort: [{time, :desc}, id: :asc], before: [:before_at, :before_id]}

        prepare {Regents.Keyfleet.Preparations.DoneBy,
                 key: :started_by_key, wallet: [:started_by_wallet, :acting_agent_wallet]}

        prepare build(
                  select: [:id, :fleet_id, :question, :started_by_key, :inserted_at],
                  load: [:stopped_at]
                )
      end
    end

    read :in_fleet do
      argument :fleet_id, :string, allow_nil?: false
      argument :id, :uuid, allow_nil?: false
      get? true

      filter expr(fleet_id == ^arg(:fleet_id) and id == ^arg(:id))
      prepare build(load: [:votes_cast, :totals])
    end

    # The poll a Key started in the last 24 hours, if it did: until that
    # poll is a day old, the Key starts no other.
    read :last_started do
      argument :fleet_id, :string, allow_nil?: false
      argument :key, :integer, allow_nil?: false
      get? true

      filter expr(
               fleet_id == ^arg(:fleet_id) and started_by_key == ^arg(:key) and
                 inserted_at > ago(24, :hour)
             )

      prepare build(sort: [inserted_at: :desc], limit: 1)
    end

    update :end do
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      accept []
      require_atomic? false
      transaction? true

      argument :fleet_id, :string, allow_nil?: false

      change Regents.Keyfleet.Polls.Changes.EndPoll
    end
  end

  policies do
    policy action(:start) do
      authorize_if {Regents.Keyfleet.Polls.Checks.Standing, role: :member}
    end

    # Only for filters that follow a vote to its poll, and for locking one.
    policy action(:read) do
      authorize_if always()
    end

    # The fleet's members, and the site finding a poll before it asks whose
    # it is (`RegentsWeb.Keyfleet.AgentPollController`).
    policy action([:listed, :started_before, :stopped_before, :in_fleet, :last_started]) do
      authorize_if {Regents.Keyfleet.Access.Check, read: :polls, scope: :fleet_id}
      authorize_if actor_attribute_equals(:role, :system)
    end

    policy action(:end) do
      authorize_if {Regents.Keyfleet.Polls.Checks.Standing, role: :starter}
    end
  end

  attributes do
    attribute :acting_agent_wallet, :string, writable?: false
    attribute :beneficiary_privy_user_id, :string, writable?: false, sensitive?: true
    attribute :agent_pairing_id, :uuid, writable?: false

    uuid_primary_key :id

    attribute :question, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 200, match: @plain_text]

    attribute :choices, {:array, :string},
      allow_nil?: false,
      public?: true,
      constraints: [
        min_length: 2,
        max_length: 10,
        items: [min_length: 1, max_length: 100, match: @plain_text]
      ]

    # What the starter adds to the question.
    attribute :notes, :string, public?: true, constraints: [max_length: 2_000]

    attribute :started_by_key, :integer,
      allow_nil?: false,
      public?: true,
      writable?: false,
      constraints: [min: 1, max: @bigint]

    attribute :started_by_wallet, :string,
      allow_nil?: false,
      public?: true,
      writable?: false,
      constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]

    attribute :closes_at, :utc_datetime_usec, allow_nil?: false, public?: true, writable?: false
    attribute :ended_at, :utc_datetime_usec, public?: true, writable?: false

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :fleet, Regents.Keyfleet.Fleets.Fleet do
      attribute_type :string
      attribute_writable? true
      allow_nil? false
      public? true
    end

    has_many :votes, Regents.Keyfleet.Polls.Vote
  end

  aggregates do
    count :votes_cast, :votes do
      authorize? false
      public? true
    end

    # Every vote's choice, for the totals once the poll has closed.
    list :vote_choices, :votes, :choice do
      authorize? false
    end
  end

  calculations do
    calculate :totals, {:array, :map}, Regents.Keyfleet.Polls.Calculations.Totals, public?: true

    # When its voting stops: when its starter ended it, or else when it closes.
    calculate :stopped_at,
              :utc_datetime_usec,
              expr(if is_nil(ended_at), do: closes_at, else: ended_at),
              public?: true
  end

  pub_sub do
    module Phoenix.PubSub
    name Regents.PubSub
    prefix "keyfleet"
    broadcast_type :phoenix_broadcast

    publish :start, ["polls", :fleet_id],
      event: "polls_changed",
      transform: fn _notification -> %{} end

    publish :end, ["polls", :fleet_id],
      event: "polls_changed",
      transform: fn _notification -> %{} end

    publish :end, ["poll", :id], event: "poll_changed", transform: fn _notification -> %{} end
  end
end
