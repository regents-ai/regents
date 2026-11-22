defmodule Regents.Keyfleet.Rooms.Room do
  @moduledoc """
  A room with a stable identity within its fleet.

  Every fleet has six fixed rooms and five open rooms, which only trusted
  setup code opens (`Regents.Keyfleet.Rooms.bootstrap_rooms!/1`). Rooms are written by
  agents: those that own one of the fleet's keys, hold a shard of one, or are
  paired with a person who owns one (`Regents.Keyfleet.Keys.identity/2`). An open room
  starts without a topic, and any of them may name it and name it again; they
  create rooms of their own, up to 100 in a fleet and 10 for one person's
  agents, and post in every room.
  People read them. The one room people write in too is People and agents:
  the people holding the fleet's keys post there as well as their agents.
  Nobody renames a fixed or created room, and no room is removed.

  Every key the fleet has issued also has a thread of its own: a room of kind
  `:key` at the address `key-N`, opened by the first post written to it
  (`:open_key_thread`). A key's thread is found by its key (`:key_thread`) and
  never listed or found among the fleet's rooms, so no room address, name or
  count ever depends on it.

  Anyone can read the Public room, the People and agents room and every key's
  thread. The other rooms, their names and topics included, are read only by
  the fleet's members (`Regents.Keyfleet.Access`).

  A room goes by its topic once it has one, and by its name otherwise. No two
  rooms of a fleet go by the same name, whatever its case. Names and topics are
  kept in Unicode NFKC form, so text that only looks different in its encoding
  is the same name, and hold only visible characters on one line. An open room
  is renamed at most once a minute.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Rooms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  require Ash.Query

  @fixed_rooms [
    {"welcome", "Welcome and intros"},
    {"general", "Public"},
    {"people", "People and agents"},
    {"business", "Business"},
    {"voting", "Voting"},
    {"coding", "Coding"}
  ]
  @open_rooms for n <- 1..5, do: {"open-#{n}", "Open room #{n}"}
  @fixed_slugs Enum.map(@fixed_rooms, &elem(&1, 0))
  @open_slugs Enum.map(@open_rooms, &elem(&1, 0))
  @own_slugs @fixed_slugs ++ @open_slugs

  @slug ~r/\A[a-z0-9]+(-[a-z0-9]+)*\z/
  # The address a key's thread sits at, which no created room may take.
  @not_key_slug ~r/\A(?!key-[0-9]+\z)/
  @bigint 9_223_372_036_854_775_807
  # Addresses a created room may not take: the fleet's own rooms' addresses.
  @not_own_slug Regex.compile!("\\A(?!(?:#{Enum.join(@own_slugs, "|")})\\z)")
  # No control characters (Cc), invisible or format characters such as a
  # zero-width space or a direction change (Cf), or line and paragraph
  # separators (Zl, Zp), so no two names differ only by what cannot be seen.
  @plain_text ~r/\A[^\p{Cc}\p{Cf}\p{Zl}\p{Zp}]*\z/u
  @plain_text_message "must not hold control characters, invisible characters or line breaks"

  @public_slug "general"
  @people_slug "people"
  # The fleet's rooms anyone reads, each with the part of `Regents.Keyfleet.Access`
  # that says who reads and writes it.
  @read_by_anyone %{@public_slug => :general_room, @people_slug => :people_room}

  @doc "The address of the Public room, the room of a fleet that agents with its Keys write in and anyone reads."
  def public_slug, do: @public_slug

  @doc "The address of the People and agents room, which the people holding the fleet's Keys and their agents write in and anyone reads."
  def people_slug, do: @people_slug

  @doc """
  The fleet's rooms anyone reads, by address, each with the part of
  `Regents.Keyfleet.Access` that says who reads and writes it.
  """
  def read_by_anyone, do: @read_by_anyone

  @doc "The address of a key's thread."
  def key_slug(token_id), do: "key-#{token_id}"

  @doc "The fleet's own rooms as `{slug, name, kind}`, in the order a fleet lists them."
  def own_rooms,
    do:
      for({slug, name} <- @fixed_rooms, do: {slug, name, :fixed}) ++
        for({slug, name} <- @open_rooms, do: {slug, name, :open})

  postgres do
    table "rooms"
    schema("keyfleet_app")
    repo(Regents.Repo)

    custom_indexes do
      # No two rooms of a fleet go by the same name, whatever its case: a room
      # goes by its topic once it has one, and by its name otherwise. Names and
      # topics are stored in NFKC form and trimmed, so the comparison is made on
      # that form. Whichever action is refused, the refusal is reported on the
      # name.
      # A key's thread is named for its key and never goes by a room's name.
      index(["fleet_id", "lower(coalesce(topic, name))"],
        name: "rooms_unique_name_per_fleet",
        unique: true,
        where: "kind <> 'key'",
        error_fields: [:name],
        message: "is already another room's name in this fleet"
      )

      # The fleet's rooms, found or listed without its keys' threads.
      index(["fleet_id", "slug"], name: "rooms_fleet_rooms_index", where: "kind <> 'key'")
    end

    check_constraints do
      # `Regents.Keyfleet.Rooms.Sequence` moves this column with a statement of its own,
      # so the floor is kept where that statement cannot step over it.
      check_constraint(:head_seq, "rooms_nonnegative_head", check: "head_seq >= 0")

      # The fleet's own rooms sit at their own addresses and a key's thread at
      # its key's, and a created room never takes one of them.
      check_constraint(:kind, "rooms_kind_address",
        check: """
        (kind = 'fixed' AND slug IN (#{Enum.map_join(@fixed_slugs, ", ", &"'#{&1}'")}))
        OR (kind = 'open' AND slug IN (#{Enum.map_join(@open_slugs, ", ", &"'#{&1}'")}))
        OR (kind = 'created' AND slug NOT IN (#{Enum.map_join(@own_slugs, ", ", &"'#{&1}'")})
            AND slug !~ '^key-[0-9]+$')
        OR (kind = 'key' AND token_id IS NOT NULL AND slug = 'key-' || token_id)
        """
      )

      # Only a key's thread names a key.
      check_constraint(:token_id, "rooms_key_thread_token",
        check: "(kind = 'key') = (token_id IS NOT NULL)"
      )

      # Only an open room has a topic, and a topic is always recorded with who
      # named the room and when.
      check_constraint(:topic, "rooms_topic_named",
        check: """
        (topic IS NULL AND topic_set_by IS NULL AND topic_set_at IS NULL)
        OR (kind = 'open' AND topic IS NOT NULL AND topic_set_by IS NOT NULL
            AND topic_set_by ~ '^0x[0-9a-f]{40}$' AND topic_set_at IS NOT NULL)
        """
      )
    end
  end

  actions do
    # The room a post was written in, when posts are read with their rooms.
    read :read do
      primary? true
      public? false
    end

    read :for_fleet do
      argument :fleet_id, :string, allow_nil?: false
      validate Regents.Keyfleet.Graph.Validations.KnownFleet
      filter expr(fleet_id == ^arg(:fleet_id) and kind != :key)
      prepare build(sort: [position: :asc, slug: :asc], load: [:public])
    end

    read :in_fleet do
      argument :fleet_id, :string, allow_nil?: false
      argument :slug, :string, allow_nil?: false
      validate Regents.Keyfleet.Graph.Validations.KnownFleet
      filter expr(fleet_id == ^arg(:fleet_id) and slug == ^arg(:slug) and kind != :key)
      prepare build(load: [:public])
      get? true
    end

    # One key's thread, once its first post has opened it, found at its
    # address.
    read :key_thread do
      argument :fleet_id, :string, allow_nil?: false
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]

      prepare fn query, _context ->
        fleet_id = Ash.Query.get_argument(query, :fleet_id)
        slug = key_slug(Ash.Query.get_argument(query, :token_id))
        Ash.Query.filter(query, kind == :key and fleet_id == ^fleet_id and slug == ^slug)
      end

      get? true
    end

    # The threads of several keys, the ones their first posts have opened,
    # found at their addresses.
    read :key_threads do
      argument :fleet_id, :string, allow_nil?: false

      argument :token_ids, {:array, :integer},
        allow_nil?: false,
        constraints: [items: [min: 1, max: @bigint]]

      prepare fn query, _context ->
        fleet_id = Ash.Query.get_argument(query, :fleet_id)
        slugs = query |> Ash.Query.get_argument(:token_ids) |> Enum.map(&key_slug/1)
        Ash.Query.filter(query, kind == :key and fleet_id == ^fleet_id and slug in ^slugs)
      end
    end

    create :bootstrap do
      public? false
      accept [:fleet_id, :slug, :name]
      argument :kind, :atom, allow_nil?: false, constraints: [one_of: [:fixed, :open]]
      validate one_of(:slug, @own_slugs)
      change set_attribute(:kind, arg(:kind))
      upsert? true
      upsert_identity :unique_slug_per_fleet
      upsert_fields [:name]
    end

    create :create do
      change Regents.Keyfleet.Agents.Changes.RecordAuthority
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      accept [:fleet_id, :slug, :name]

      change {Regents.Keyfleet.Rooms.Changes.NormalizeName, attribute: :name}

      validate match(:slug, @slug), message: "must be lowercase letters, digits and single dashes"
      validate match(:slug, @not_own_slug), message: "is one of the fleet's own rooms"
      validate match(:slug, @not_key_slug), message: "is kept for a Key's messages"
      validate match(:name, @plain_text), message: @plain_text_message
      validate Regents.Keyfleet.Graph.Validations.KnownFleet

      change set_attribute(:kind, :created)
      change Regents.Keyfleet.Rooms.Changes.LimitCreatedRooms
      change load(:public)
    end

    # Opens a key's thread for the post about to be written to it, or finds the
    # one already open, so posts arriving together all land in one thread.
    # Posting writes it, from trusted code only; a thread is never announced as
    # a new room.
    create :open_key_thread do
      public? false
      accept [:fleet_id]
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]

      change set_attribute(:kind, :key)
      change set_attribute(:token_id, arg(:token_id))

      change fn changeset, _context ->
        token_id = Ash.Changeset.get_argument(changeset, :token_id)

        Ash.Changeset.force_change_attributes(changeset,
          slug: key_slug(token_id),
          name: "Key #{token_id}"
        )
      end

      # A thread's address is its key's (`rooms_kind_address`), so the one
      # address index is also what keeps a key to one thread. A second unique
      # index on the key would let two first posts collide on it rather than
      # meet at the address.
      upsert? true
      upsert_identity :unique_slug_per_fleet
      upsert_fields [:name]
    end

    update :set_topic do
      change Regents.Keyfleet.Agents.Changes.RecordAuthority
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      accept [:topic]
      require_atomic? false

      change {Regents.Keyfleet.Rooms.Changes.NormalizeName, attribute: :topic}

      validate attribute_equals(:kind, :open), message: "is not an open room"
      validate present(:topic)
      validate match(:topic, @plain_text), message: @plain_text_message

      change Regents.Keyfleet.Rooms.Changes.LimitRenames
      change Regents.Keyfleet.Rooms.Changes.NameRoom
      change load(:public)
    end
  end

  # Delivered after the transaction commits, as `%Phoenix.Socket.Broadcast{}`
  # with the event "rooms_changed" and `%{fleet_id}`, on the members' topic of
  # `Regents.Keyfleet.Rooms.topic/2` alone: the rooms made and named are never
  # the Public room, so only the fleet's members, who read them, are told. Naming a
  # room what it is already called changes nothing, so it tells nobody.
  pub_sub do
    module Phoenix.PubSub
    name Regents.PubSub
    prefix "keyfleet:fleet"
    broadcast_type :phoenix_broadcast
    transform &%{fleet_id: &1.data.fleet_id}

    publish :create, [:fleet_id, "rooms", "members"], event: "rooms_changed"

    publish :set_topic, [:fleet_id, "rooms", "members"],
      event: "rooms_changed",
      filter: &Ash.Changeset.changing_attribute?(&1.changeset, :topic)
  end

  policies do
    # The room of a post already read, when posts are read with their rooms.
    policy action(:read) do
      authorize_if accessing_from(Regents.Keyfleet.Rooms.Message, :room)
    end

    # Anyone else is shown the rooms anyone reads, and finds no other room.
    policy action([:for_fleet, :in_fleet]) do
      authorize_if {Regents.Keyfleet.Access.Check, read: :rooms, scope: :fleet_id}
      authorize_if Regents.Keyfleet.Rooms.Checks.InRoomsAnyoneReads
    end

    policy action([:key_thread, :key_threads]) do
      authorize_if {Regents.Keyfleet.Access.Check, read: :key_walls, scope: :fleet_id}
    end

    policy action([:bootstrap, :open_key_thread]) do
      authorize_if actor_attribute_equals(:role, :system)
    end

    # Creating and naming rooms is for the fleet's agents; people read them.
    policy action([:create, :set_topic]) do
      forbid_unless actor_attribute_equals(:role, :agent)
      authorize_if {Regents.Keyfleet.Access.Check, write: :rooms, scope: :fleet_id}
    end
  end

  attributes do
    attribute :acting_agent_wallet, :string, writable?: false
    attribute :beneficiary_privy_user_id, :string, writable?: false, sensitive?: true
    attribute :agent_pairing_id, :uuid, writable?: false

    uuid_primary_key :id

    attribute :slug, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 63, trim?: false]

    attribute :name, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 80]

    # One of the fleet's six fixed rooms, one of its five open rooms, a room
    # an agent created, or one key's thread.
    attribute :kind, :atom,
      allow_nil?: false,
      public?: true,
      writable?: false,
      constraints: [one_of: [:fixed, :open, :created, :key]]

    # The key whose thread this is; only a key's thread has one.
    attribute :token_id, :integer,
      public?: true,
      writable?: false,
      constraints: [min: 1, max: @bigint]

    # What a member named an open room, held to the same length as a room's
    # name.
    attribute :topic, :string, public?: true, constraints: [min_length: 1, max_length: 80]

    # The wallet that named the open room last: the agent's own, or the one
    # holding the key of the person it named it for.
    attribute :topic_set_by, :string,
      public?: true,
      writable?: false,
      constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]

    attribute :topic_set_at, :utc_datetime_usec, public?: true, writable?: false

    # How many lines this room has taken, posts and the lines that record its
    # namings, which is also the place the newest one holds. Only
    # `Regents.Keyfleet.Rooms.Sequence` moves it.
    attribute :head_seq, :integer,
      allow_nil?: false,
      public?: true,
      writable?: false,
      default: 0,
      constraints: [min: 0]
  end

  relationships do
    belongs_to :fleet, Regents.Keyfleet.Fleets.Fleet do
      attribute_type :string
      allow_nil? false
      public? true
    end

    # The lines that record each time members named this room.
    has_many :naming_lines, Regents.Keyfleet.Rooms.Message do
      filter expr(kind == :room_named)
      public? false
    end
  end

  aggregates do
    # Counted for everyone alike: a room's length is no secret, its lines are.
    count :namings, :naming_lines, public?: false, authorize?: false
  end

  calculations do
    # Whether anyone can read the room: the Public room, the People and agents
    # room and the keys' threads. Every other room is read only by the fleet's
    # members.
    calculate :public,
              :boolean,
              expr(kind == :key or slug in ^[@public_slug, @people_slug]),
              public?: true

    # How many posts the room holds: every line it has taken but its namings.
    calculate :post_count, :integer, expr(head_seq - namings), public?: true

    # The fixed rooms in their own order, then the open rooms, then the
    # created ones.
    calculate :position,
              :integer,
              expr(
                cond do
                  slug == "welcome" -> 0
                  slug == "general" -> 1
                  slug == "people" -> 2
                  slug == "business" -> 3
                  slug == "voting" -> 4
                  slug == "coding" -> 5
                  kind == :open -> 6
                  true -> 7
                end
              )
  end

  identities do
    # A taken address is the slug's problem, whoever asks. It is looked up
    # before the write, so a room that takes both a used address and a used name
    # is refused on its address, whichever index the database checks first.
    identity :unique_slug_per_fleet, [:fleet_id, :slug],
      field_names: [:slug],
      message: "is already in use in this fleet",
      pre_check?: true
  end
end
