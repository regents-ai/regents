defmodule Regents.Keyfleet.Agents.CheckIn do
  @moduledoc """
  When one agent last checked in with one fleet, and what kind of check-in
  each was, so its status can be told from when its check-ins arrived
  (`Regents.Keyfleet.Agents.CheckInStatus`).

  An agent checks in each time it syncs with the fleet, saying whether it is
  in a conversation (`session`) or running on a schedule it names
  (`scheduled`, every so many minutes). A schedule is confirmed once two
  scheduled check-ins arrive about one interval apart, and the row counts
  every scheduled check-in, the times the agent came back on its own. The row
  also keeps when the agent last did something here, and what: a post, a task
  joined, forked or handed in, a review, another workspace write, a notebook edit or a push.

  A check-in may also say, in the agent's own words, what is blocking it
  (`blocker`), kept until its next check-in, which clears it unless it says
  one again. Only the agent and the person it checked in for read it.

  Every time is the database's, and each kind of write happens at most once a
  minute (a contribution of a new kind at once), in one statement that inserts the row or updates it. Anyone may
  read the rest; only the agent itself writes its own rows.

  A scheduled check-in that is written tells the open pages of the agent's
  person, and only theirs, once it commits: `:agents_changed` on
  `RegentAgents.topic/1`, where the person's pages already hear their agents
  pair and unpair. One skipped as too soon after the last tells nobody.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Agents,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias Regents.Keyfleet.Agents.CheckInStatus

  @contribution_kinds [:post, :task, :submit, :review, :workspace, :notebook, :code]

  # What blocks the agent: one line of plain text, read at a glance beside its
  # check-in, so no longer than a short post (280 characters) and with no
  # control or invisible characters and no line breaks. It is trimmed, and an
  # empty line is none.
  @blocker [max_length: 280, match: ~r/\A[^\p{Cc}\p{Cf}\p{Zl}\p{Zp}]*\z/u]

  @doc "Whether a check-in takes `line` as what blocks the agent (`blocker`)."
  def blocker?(line) when is_binary(line),
    do: match?({:ok, _line}, Ash.Type.apply_constraints(Ash.Type.String, line, @blocker))

  def blocker?(_line), do: false

  postgres do
    table "agent_check_ins"
    schema("keyfleet_app")
    repo(Regents.Repo)

    check_constraints do
      check_constraint(:schedule_minutes, "agent_check_ins_schedule_minutes",
        check: "schedule_minutes BETWEEN 10 AND 1440"
      )

      # Only a declared schedule can be confirmed.
      check_constraint(:schedule_confirmed_at, "agent_check_ins_confirmed_schedule",
        check: "schedule_confirmed_at IS NULL OR schedule_minutes IS NOT NULL"
      )

      check_constraint(:last_contribution_kind, "agent_check_ins_contribution_kind",
        check:
          "last_contribution_kind IN ('post', 'task', 'submit', 'review', 'workspace', 'notebook', 'code')"
      )

      # A contribution has both its time and its kind, or neither.
      check_constraint(:last_contribution_at, "agent_check_ins_contribution_whole",
        check: "(last_contribution_at IS NULL) = (last_contribution_kind IS NULL)"
      )
    end
  end

  actions do
    read :read do
      primary? true
    end

    # These agents' check-ins with the fleet, to show beside the keys they run.
    read :in_fleet do
      argument :fleet_id, :string, allow_nil?: false

      argument :agent_profile_ids, {:array, :uuid},
        allow_nil?: false,
        constraints: [max_length: 100]

      filter expr(fleet_id == ^arg(:fleet_id) and agent_profile_id in ^arg(:agent_profile_ids))
      prepare build(load: [:last_seen_at])
    end

    # What these agents last said was blocking them, in each fleet where they
    # said something, for the person they checked in for, the latest first.
    read :blocked do
      argument :wallets, {:array, :string}, allow_nil?: false, constraints: [max_length: 100]

      filter expr(
               acting_agent_wallet in ^arg(:wallets) and
                 beneficiary_privy_user_id == ^actor(:privy_user_id) and not is_nil(blocker)
             )

      prepare build(sort: [last_check_in_at: :desc])
    end

    # A check-in from an agent in a conversation.
    create :check_in_session do
      change Regents.Keyfleet.Agents.Changes.RecordAuthority
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      public? false
      accept [:agent_profile_id, :fleet_id]
      argument :blocker, :string

      upsert? true

      upsert_fields [
        :blocker,
        :acting_agent_wallet,
        :beneficiary_privy_user_id,
        :agent_pairing_id
      ]

      upsert_condition expr(
                         is_nil(last_session_at) or
                           last_session_at <
                             fragment(
                               "(statement_timestamp() AT TIME ZONE 'utc') - make_interval(secs => ?)",
                               ^CheckInStatus.spacing_seconds()
                             )
                       )

      return_skipped_upsert? true

      change set_attribute(:blocker, arg(:blocker))

      change atomic_set(
               :last_check_in_at,
               expr(fragment("(statement_timestamp() AT TIME ZONE 'utc')"))
             )

      change atomic_update(
               :last_check_in_at,
               expr(fragment("(statement_timestamp() AT TIME ZONE 'utc')"))
             )

      change atomic_set(
               :last_session_at,
               expr(fragment("(statement_timestamp() AT TIME ZONE 'utc')"))
             )

      change atomic_update(
               :last_session_at,
               expr(fragment("(statement_timestamp() AT TIME ZONE 'utc')"))
             )
    end

    # A check-in an agent makes on its own schedule, every `every_minutes`.
    create :check_in_scheduled do
      change Regents.Keyfleet.Agents.Changes.RecordAuthority
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      public? false
      accept [:agent_profile_id, :fleet_id]

      argument :every_minutes, :integer,
        allow_nil?: false,
        constraints: [
          min: CheckInStatus.schedule_minutes().first,
          max: CheckInStatus.schedule_minutes().last
        ]

      argument :blocker, :string

      upsert? true

      upsert_fields [
        :schedule_minutes,
        :blocker,
        :acting_agent_wallet,
        :beneficiary_privy_user_id,
        :agent_pairing_id
      ]

      upsert_condition expr(
                         is_nil(last_scheduled_at) or
                           last_scheduled_at <
                             fragment(
                               "(statement_timestamp() AT TIME ZONE 'utc') - make_interval(secs => ?)",
                               ^CheckInStatus.spacing_seconds()
                             )
                       )

      return_skipped_upsert? true

      change set_attribute(:schedule_minutes, arg(:every_minutes))
      change set_attribute(:blocker, arg(:blocker))
      change Regents.Keyfleet.Agents.Changes.ScheduledCheckIn, only_when_valid?: true
    end

    # The agent did something here (`@contribution_kinds`): something new is
    # written at once, a repeat of the last kind at most once a minute. An
    # agent that contributes has just made a signed request, so a first row
    # counts it as checking in.
    create :note_contribution do
      change Regents.Keyfleet.Agents.Changes.RecordAuthority
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      public? false
      accept [:agent_profile_id, :fleet_id]

      argument :kind, :atom, allow_nil?: false, constraints: [one_of: @contribution_kinds]

      upsert? true

      upsert_fields [
        :last_contribution_kind,
        :acting_agent_wallet,
        :beneficiary_privy_user_id,
        :agent_pairing_id
      ]

      upsert_condition expr(
                         is_nil(last_contribution_at) or
                           last_contribution_kind != ^arg(:kind) or
                           last_contribution_at <
                             fragment(
                               "(statement_timestamp() AT TIME ZONE 'utc') - make_interval(secs => ?)",
                               ^CheckInStatus.spacing_seconds()
                             )
                       )

      return_skipped_upsert? true

      change set_attribute(:last_contribution_kind, arg(:kind))

      change atomic_set(
               :last_check_in_at,
               expr(fragment("(statement_timestamp() AT TIME ZONE 'utc')"))
             )

      change atomic_set(
               :last_contribution_at,
               expr(fragment("(statement_timestamp() AT TIME ZONE 'utc')"))
             )

      change atomic_update(
               :last_contribution_at,
               expr(fragment("(statement_timestamp() AT TIME ZONE 'utc')"))
             )
    end
  end

  pub_sub do
    module Phoenix.PubSub
    name Regents.PubSub
    prefix "regent_agents"
    filter &(!Ash.Resource.get_metadata(&1.data, :upsert_skipped))

    publish :check_in_scheduled, [:beneficiary_privy_user_id],
      transform: fn _notification -> :agents_changed end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:blocked) do
      authorize_if actor_attribute_equals(:role, :person)
    end

    policy action([:check_in_session, :check_in_scheduled, :note_contribution]) do
      authorize_if Regents.Keyfleet.Agents.Checks.OwnProfile
    end
  end

  field_policies do
    # The agent's own words on what blocks it: for the agent itself, and for
    # the person it checked in for, signed in as themselves.
    field_policy :blocker do
      authorize_if expr(
                     ^actor(:role) == :agent and acting_agent_wallet == ^actor(:wallet_address)
                   )

      authorize_if expr(
                     ^actor(:role) == :person and
                       beneficiary_privy_user_id == ^actor(:privy_user_id)
                   )
    end

    field_policy :* do
      authorize_if always()
    end
  end

  attributes do
    attribute :acting_agent_wallet, :string, writable?: false
    attribute :beneficiary_privy_user_id, :string, writable?: false, sensitive?: true
    attribute :agent_pairing_id, :uuid, writable?: false

    attribute :last_check_in_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :last_session_at, :utc_datetime_usec, public?: true
    attribute :last_scheduled_at, :utc_datetime_usec, public?: true
    # The scheduled check-in the next one's gap is measured from.
    attribute :counted_scheduled_at, :utc_datetime_usec, public?: true

    attribute :schedule_minutes, :integer,
      public?: true,
      constraints: [
        min: CheckInStatus.schedule_minutes().first,
        max: CheckInStatus.schedule_minutes().last
      ]

    attribute :schedule_confirmed_at, :utc_datetime_usec, public?: true
    attribute :last_contribution_at, :utc_datetime_usec, public?: true

    attribute :last_contribution_kind, :atom,
      public?: true,
      constraints: [one_of: @contribution_kinds]

    # What the agent said was blocking it at its last check-in, nil when it
    # said nothing.
    attribute :blocker, :string, public?: true, constraints: @blocker

    # Every scheduled check-in it has made here.
    attribute :scheduled_check_ins, :integer,
      allow_nil?: false,
      default: 0,
      public?: true,
      constraints: [min: 0]
  end

  calculations do
    # When the agent was last seen in the fleet: its last check-in, or its last
    # contribution if that came later.
    calculate :last_seen_at,
              :utc_datetime_usec,
              expr(
                if is_nil(last_contribution_at) or last_contribution_at < last_check_in_at do
                  last_check_in_at
                else
                  last_contribution_at
                end
              )
  end

  relationships do
    belongs_to :agent_profile, Regents.Keyfleet.Agents.AgentProfile do
      primary_key? true
      allow_nil? false
      public? true
    end

    belongs_to :fleet, Regents.Keyfleet.Fleets.Fleet do
      attribute_type :string
      primary_key? true
      allow_nil? false
      public? true
    end
  end
end
