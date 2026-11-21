defmodule Regents.Keyfleet.Polls.Vote do
  @moduledoc """
  A Key's one vote in a poll: the choice it made, and a short reason if it
  gives one.

  A Key votes once in a poll, whichever of its agents sends it: sending the
  same choice again answers the vote it already has, and a different choice
  is refused. Votes are never changed or removed. The fleet's Key holders
  read each vote once the poll has closed; until then nobody does.
  """
  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Keyfleet.Polls,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  @bigint 9_223_372_036_854_775_807

  postgres do
    table "poll_votes"
    schema("keyfleet_app")
    repo(Regents.Repo)

    references do
      reference(:poll, on_delete: :restrict)
    end

    check_constraints do
      check_constraint(:token_id, "poll_votes_token_id", check: "token_id > 0")
      check_constraint(:wallet, "poll_votes_wallet_shape", check: "wallet ~ '^0x[0-9a-f]{40}$'")
    end

    custom_statements do
      statement :poll_votes_function do
        up("""
        CREATE FUNCTION keyfleet_app.protect_poll_vote() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
          RAISE EXCEPTION 'poll votes cannot be changed or deleted' USING ERRCODE = '23514';
        END;
        $$;
        """)

        down("DROP FUNCTION keyfleet_app.protect_poll_vote();")
      end

      statement :poll_votes_trigger do
        up("""
        CREATE TRIGGER protect_poll_votes BEFORE UPDATE OR DELETE ON keyfleet_app.poll_votes
        FOR EACH ROW EXECUTE FUNCTION keyfleet_app.protect_poll_vote();
        """)

        down("DROP TRIGGER protect_poll_votes ON keyfleet_app.poll_votes;")
      end
    end
  end

  actions do
    create :cast do
      change Regents.Keyfleet.Agents.Changes.RecordAuthority
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      validate Regents.Keyfleet.Polls.Validations.AgentVoting, before_action?: true
      accept [:choice, :reason]
      transaction? true

      argument :fleet_id, :string, allow_nil?: false
      argument :poll_id, :uuid, allow_nil?: false

      # The Key's own vote settles a repeat: the database hands back the vote
      # it already has.
      upsert? true
      upsert_identity :unique_vote
      upsert_fields []
      upsert_condition expr(false)
      return_skipped_upsert? true

      change Regents.Keyfleet.Polls.Changes.CastVote
    end

    # Only for checking whether a Key has voted.
    read :read do
      primary? true
      public? false
    end

    # Every vote in a closed poll of the fleet, in the order they came.
    read :in_poll do
      argument :fleet_id, :string, allow_nil?: false
      argument :poll_id, :uuid, allow_nil?: false

      filter expr(
               poll_id == ^arg(:poll_id) and poll.fleet_id == ^arg(:fleet_id) and
                 (not is_nil(poll.ended_at) or poll.closes_at <= now())
             )

      prepare build(sort: [inserted_at: :asc, id: :asc])
    end

    # The actor's own Key's vote in a poll of the fleet.
    read :mine do
      argument :fleet_id, :string, allow_nil?: false
      argument :poll_id, :uuid, allow_nil?: false
      get? true

      filter expr(poll_id == ^arg(:poll_id) and poll.fleet_id == ^arg(:fleet_id))
      prepare Regents.Keyfleet.Polls.Preparations.OwnVote
    end
  end

  policies do
    policy action(:cast) do
      authorize_if {Regents.Keyfleet.Polls.Checks.Standing, role: :member}
    end

    policy action([:in_poll, :mine]) do
      authorize_if {Regents.Keyfleet.Polls.Checks.Standing, role: :member}
    end

    policy action(:read) do
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

    attribute :choice, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 100]

    attribute :reason, :string,
      public?: true,
      constraints: [min_length: 1, max_length: 500]

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :poll, Regents.Keyfleet.Polls.Poll do
      attribute_writable? false
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_vote, [:poll_id, :token_id]
  end

  pub_sub do
    module Phoenix.PubSub
    name Regents.PubSub
    prefix "keyfleet"
    broadcast_type :phoenix_broadcast

    publish :cast, ["poll", :poll_id],
      event: "poll_changed",
      transform: fn _notification -> %{} end
  end

  @doc "The vote as agents read it."
  def to_map(vote),
    do: %{key: vote.token_id, choice: vote.choice, reason: vote.reason, at: vote.inserted_at}
end
