defmodule Regents.Keyfleet.Dms.Message do
  @moduledoc """
  One direct message from one Key of a fleet to another, in their
  conversation. Its words come with up to eight parts (`Regents.Keyfleet.Dms.Part`):
  more text, a small JSON object, or a link, which is how a file is sent.

  `seq` is the message's place among every direct message, given by the
  database and only ever growing, so a reader carries on after the last one it
  saw. The fleet's messages are written one at a time
  (`Regents.Keyfleet.Dms.Changes.SendMessage`), so within a fleet that order is the
  order they become readable.

  Messages are never edited. Each side of a conversation keeps its own view of
  them (`kept_for/1`): a side drops what it cleared and what is older than its
  auto-delete days (`Regents.Keyfleet.Dms.Conversation`). The hourly job removes a
  message once neither side keeps it (`:remove_expired`).

  Each message keeps both Keys' ownership epochs from when it was sent. When a
  Key changes hands, its new holder sees only messages from then on: every
  read shows a Key's holder only the messages it sent or received in its
  current epoch (`shown_to`). Nothing older is deleted; the other side still
  sees all of it, by the same rule for its own Key.
  """
  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Keyfleet.Dms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub],
    extensions: [AshOban]

  alias Regents.Account.Actors.System

  @bigint 9_223_372_036_854_775_807
  @max_body 4_000
  @max_parts 8
  @max_page 200

  postgres do
    table "dm_messages"
    schema("keyfleet_app")
    repo(Regents.Repo)
    migration_types(seq: :bigserial)
    migration_defaults(inserted_at: "fragment(\"(clock_timestamp() AT TIME ZONE 'utc')\")")

    references do
      reference(:conversation, on_delete: :delete)
    end

    check_constraints do
      check_constraint(:to_token_id, "dm_messages_two_keys",
        check: "from_token_id > 0 AND to_token_id > 0 AND from_token_id <> to_token_id"
      )

      check_constraint(:body, "dm_messages_body_length",
        check: "length(body) BETWEEN 1 AND #{@max_body}"
      )

      check_constraint(:author_wallet, "dm_messages_author_wallet_shape",
        check: "author_wallet ~ '^0x[0-9a-f]{40}$'"
      )
    end

    custom_indexes do
      # One conversation in order, and its messages by age for auto-delete.
      index([:conversation_id, :seq])
      index([:conversation_id, :inserted_at])

      # What one Key sent and received, in order, for catching up.
      index([:fleet_id, :from_token_id, :seq])

      # What one Key sent in the last hour, for its hourly limit.
      index([:fleet_id, :from_token_id, :inserted_at])
      index([:fleet_id, :to_token_id, :seq])

      # The words of the messages, as a search matches them (`:search`).
      index(["to_tsvector('english', body)"],
        name: "dm_messages_search_index",
        using: "gin",
        concurrently: true
      )
    end
  end

  oban do
    scheduled_actions do
      # Every hour, the messages neither side keeps.
      schedule :remove_expired, "0 * * * *" do
        action :remove_expired
        queue(:keyfleet_default)
        worker_module_name(Regents.Keyfleet.Dms.Message.AshOban.ActionWorker.RemoveExpired)
      end
    end
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :send do
      change Regents.Keyfleet.Agents.Changes.RecordAuthority
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      accept []
      transaction? true

      argument :fleet_id, :string, allow_nil?: false
      argument :from_token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :to_token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]

      argument :body, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: @max_body, trim?: true]

      argument :parts, {:array, Regents.Keyfleet.Dms.Part},
        allow_nil?: false,
        default: [],
        constraints: [max_length: @max_parts, nil_items?: false]

      argument :idempotency_key, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 128, trim?: false]

      # The sending Key's own send key settles a repeat: the database hands back
      # the message it already sent rather than writing a second.
      upsert? true
      upsert_identity :unique_send_key
      upsert_fields []
      upsert_condition expr(false)
      return_skipped_upsert? true

      validate Regents.Keyfleet.Graph.Validations.KnownFleet
      # The box on the page is drawn before it holds anything; these wait for
      # both Keys, and an empty one is refused as required.
      validate {Regents.Keyfleet.Rooms.Validations.IssuedKey, argument: :to_token_id},
        where: present([:fleet_id, :to_token_id])

      validate {Regents.Keyfleet.Dms.Validations.TwoKeys, from: :from_token_id, to: :to_token_id},
        where: present([:from_token_id, :to_token_id])

      change Regents.Keyfleet.Dms.Changes.SendMessage
      change Regents.Keyfleet.Dms.Changes.LimitSends
    end

    # The conversation between two Keys, oldest first, after a place in it, as
    # Key `token_id`'s holder may see it.
    read :in_conversation do
      argument :fleet_id, :string, allow_nil?: false
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :other_token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :after_seq, :integer, default: 0, constraints: [min: 0, max: @bigint]
      argument :limit, :integer, default: 100, constraints: [min: 1, max: @max_page]

      validate Regents.Keyfleet.Graph.Validations.KnownFleet

      filter expr(
               fleet_id == ^arg(:fleet_id) and
                 ((from_token_id == ^arg(:token_id) and to_token_id == ^arg(:other_token_id)) or
                    (from_token_id == ^arg(:other_token_id) and to_token_id == ^arg(:token_id)))
             )

      filter expr(seq > ^arg(:after_seq) and shown_to(token_id: ^arg(:token_id)))

      prepare build(load: [:via_agent])
      prepare Regents.Keyfleet.Dms.Preparations.InOrder
      metadata :more_after, :boolean, allow_nil?: false
    end

    # The newest messages between two Keys, newest first, for the page, as Key
    # `token_id`'s holder may see them.
    read :latest do
      argument :fleet_id, :string, allow_nil?: false
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :other_token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :limit, :integer, default: 100, constraints: [min: 1, max: @max_page]

      validate Regents.Keyfleet.Graph.Validations.KnownFleet

      filter expr(
               fleet_id == ^arg(:fleet_id) and
                 ((from_token_id == ^arg(:token_id) and to_token_id == ^arg(:other_token_id)) or
                    (from_token_id == ^arg(:other_token_id) and to_token_id == ^arg(:token_id)))
             )

      filter expr(shown_to(token_id: ^arg(:token_id)))

      prepare build(load: [:via_agent])
      prepare {Regents.Keyfleet.Preparations.NewestFirst, sort: [seq: :desc], before: []}
    end

    # The messages to or from any of the Keys, each Key read after its own
    # place (the `n`th Key after the `n`th place in `after_seqs`), oldest first,
    # in each Key's current ownership epoch, without those sent to one of them
    # by a Key it has blocked. The lowest place bounds the whole read, so the
    # read starts there.
    read :changes do
      argument :fleet_id, :string, allow_nil?: false

      argument :token_ids, {:array, :integer},
        allow_nil?: false,
        constraints: [items: [min: 1, max: @bigint]]

      argument :after_seqs, {:array, :integer},
        allow_nil?: false,
        constraints: [items: [min: 0, max: @bigint]]

      argument :limit, :integer, default: 50, constraints: [min: 1, max: @max_page]

      validate Regents.Keyfleet.Graph.Validations.KnownFleet

      filter expr(
               fleet_id == ^arg(:fleet_id) and
                 seq >
                   fragment(
                     "(SELECT min(place) FROM unnest(?::bigint[]) AS place)",
                     ^arg(:after_seqs)
                   ) and
                 ((from_token_id in ^arg(:token_ids) and sent_in_current_epoch and
                     kept_by_sender and
                     seq >
                       fragment(
                         "(?::bigint[])[array_position(?::bigint[], ?::bigint)]",
                         ^arg(:after_seqs),
                         ^arg(:token_ids),
                         from_token_id
                       )) or
                    (to_token_id in ^arg(:token_ids) and received_in_current_epoch and
                       kept_by_recipient and not sender_blocked and
                       seq >
                         fragment(
                           "(?::bigint[])[array_position(?::bigint[], ?::bigint)]",
                           ^arg(:after_seqs),
                           ^arg(:token_ids),
                           to_token_id
                         )))
             )

      prepare Regents.Keyfleet.Dms.Preparations.InOrder
      metadata :more_after, :boolean, allow_nil?: false
    end

    # Incoming messages for feed catch-up. The caller adds its time window or
    # the sequence from a live notice and bounds the page.
    read :incoming do
      argument :fleet_id, :string, allow_nil?: false

      argument :token_ids, {:array, :integer},
        allow_nil?: false,
        constraints: [items: [min: 1, max: @bigint]]

      validate Regents.Keyfleet.Graph.Validations.KnownFleet

      filter expr(
               fleet_id == ^arg(:fleet_id) and to_token_id in ^arg(:token_ids) and
                 from_token_id not in ^arg(:token_ids) and received_in_current_epoch and
                 kept_by_recipient and not sender_blocked
             )

      prepare build(sort: [seq: :asc])
    end

    # The messages to or from any of the Keys whose words match a search, a
    # page at a time (`Regents.Keyfleet.Search`), as each Key's holder sees them in
    # `:changes`: in the Key's current ownership epoch, kept on its side, and
    # without those sent to it by a Key it has blocked. Words are matched as
    # English, through the messages' search index (`dm_messages_search_index`).
    read :search do
      argument :fleet_id, :string, allow_nil?: false

      argument :token_ids, {:array, :integer},
        allow_nil?: false,
        constraints: [items: [min: 1, max: @bigint]]

      argument :query, :string, allow_nil?: false, constraints: [max_length: 200, trim?: false]
      argument :before_at, :utc_datetime_usec
      argument :before_kind, :string
      argument :before_id, :string
      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: @max_page]

      filter expr(
               fleet_id == ^arg(:fleet_id) and
                 ((from_token_id in ^arg(:token_ids) and sent_in_current_epoch and
                     kept_by_sender) or
                    (to_token_id in ^arg(:token_ids) and received_in_current_epoch and
                       kept_by_recipient and not sender_blocked)) and
                 fragment(
                   "to_tsvector('english', ?) @@ websearch_to_tsquery('english', ?)",
                   body,
                   ^arg(:query)
                 )
             )

      prepare build(load: [:via_agent, match: [query: arg(:query)]])
      prepare {Regents.Keyfleet.Preparations.SearchPage, kind: "dm", at: :inserted_at, id: :id}
    end

    # What one Key sent in the last hour, newest first, by the database's
    # clock, for its hourly limit (`Regents.Keyfleet.Dms.Changes.LimitSends`).
    read :sent_last_hour do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :token_id, :integer, allow_nil?: false

      filter expr(
               fleet_id == ^arg(:fleet_id) and from_token_id == ^arg(:token_id) and
                 inserted_at > fragment("(now() AT TIME ZONE 'utc') - interval '1 hour'")
             )

      prepare build(select: [:id, :inserted_at], sort: [inserted_at: :desc])
    end

    # The messages neither side of their conversation keeps.
    read :expired do
      public? false

      filter expr(not kept_by_sender and not kept_by_recipient)
    end

    destroy :expire do
      public? false
    end

    # Run every hour by the scheduled job above.
    action :remove_expired do
      run fn _input, _context ->
        __MODULE__
        |> Ash.Query.for_read(:expired, %{}, actor: %System{})
        |> Ash.bulk_destroy!(:expire, %{},
          actor: %System{},
          strategy: [:atomic, :stream],
          return_errors?: true
        )

        :ok
      end
    end
  end

  # Delivered after the message commits, as `%Phoenix.Socket.Broadcast{}` on
  # `Regents.Keyfleet.Dms.inbox_topic/2` of the Key that sent it and the Key it went
  # to: "dm_head" with `%{conversation_id, seq, from_token_id}`. A repeat the
  # database handed back is not announced.
  pub_sub do
    module Phoenix.PubSub
    name Regents.PubSub
    prefix "keyfleet:dms"
    broadcast_type :phoenix_broadcast
    filter &(!Ash.Resource.get_metadata(&1.data, :upsert_skipped))

    publish :send, [:fleet_id, :from_token_id], event: "dm_head", transform: &__MODULE__.head/1
    publish :send, [:fleet_id, :to_token_id], event: "dm_head", transform: &__MODULE__.head/1
  end

  @doc false
  def head(%{data: message}),
    do: %{
      conversation_id: message.conversation_id,
      seq: message.seq,
      from_token_id: message.from_token_id
    }

  policies do
    policy action(:send) do
      authorize_if {Regents.Keyfleet.Dms.Checks.KeyHolder, keys: [:from_token_id]}
    end

    policy action([:in_conversation, :latest]) do
      authorize_if {Regents.Keyfleet.Dms.Checks.KeyHolder, keys: [:token_id]}
    end

    policy action([:changes, :incoming, :search]) do
      authorize_if {Regents.Keyfleet.Dms.Checks.KeyHolder, keys: [:token_ids]}
    end

    policy action([:read, :sent_last_hour, :expired, :expire]) do
      authorize_if actor_attribute_equals(:role, :system)
    end

    policy action(:remove_expired) do
      authorize_if AshOban.Checks.AshObanInteraction
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    attribute :acting_agent_wallet, :string, writable?: false
    attribute :beneficiary_privy_user_id, :string, writable?: false, sensitive?: true
    attribute :agent_pairing_id, :uuid, writable?: false

    uuid_primary_key :id

    attribute :seq, :integer,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true,
      constraints: [min: 1, max: @bigint]

    attribute :from_token_id, :integer,
      allow_nil?: false,
      writable?: false,
      public?: true,
      constraints: [min: 1, max: @bigint]

    attribute :to_token_id, :integer,
      allow_nil?: false,
      writable?: false,
      public?: true,
      constraints: [min: 1, max: @bigint]

    attribute :body, :string,
      allow_nil?: false,
      writable?: false,
      public?: true,
      constraints: [min_length: 1, max_length: @max_body, trim?: false]

    attribute :parts, {:array, Regents.Keyfleet.Dms.Part},
      allow_nil?: false,
      default: [],
      writable?: false,
      public?: true

    # The wallet the message came from: the person's wallet holding the Key,
    # or the agent's own.
    attribute :author_wallet, :string,
      allow_nil?: false,
      writable?: false,
      public?: true,
      constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]

    # The sending Key's ownership epoch it was sent in. A send key names one
    # message per Key and holder, so a Key's new holder starts afresh.
    attribute :from_ownership_epoch, :integer,
      allow_nil?: false,
      writable?: false,
      public?: false,
      constraints: [min: 1, max: @bigint]

    # The receiving Key's ownership epoch when it arrived.
    attribute :to_ownership_epoch, :integer,
      allow_nil?: false,
      writable?: false,
      public?: false,
      constraints: [min: 1, max: @bigint]

    attribute :idempotency_key, :string,
      allow_nil?: false,
      writable?: false,
      public?: false,
      constraints: [min_length: 1, max_length: 128, trim?: false]

    attribute :inserted_at, :utc_datetime_usec,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true
  end

  relationships do
    belongs_to :fleet, Regents.Keyfleet.Fleets.Fleet do
      attribute_type :string
      attribute_writable? false
      allow_nil? false
      public? true
    end

    belongs_to :conversation, Regents.Keyfleet.Dms.Conversation do
      attribute_writable? false
      allow_nil? false
      public? true
    end

    # The agent that wrote it, for its Key or for the person it is paired
    # with; nil when a person wrote it.
    belongs_to :via_agent, Regents.Keyfleet.Agents.AgentProfile do
      attribute_writable? false
      public? true
      read_action :public_profile
    end
  end

  calculations do
    # The words around what a search matched in the message, at most 24 of them.
    calculate :match,
              :string,
              expr(
                fragment(
                  ~S|ts_headline('english', ?, websearch_to_tsquery('english', ?), 'StartSel="", StopSel="", MaxWords=24, MinWords=8')|,
                  body,
                  ^arg(:query)
                )
              ) do
      argument :query, :string, allow_nil?: false, constraints: [trim?: false]
    end

    # Whether Key `token_id`'s holder now may see the message: it is one side
    # of it, the message was sent or received in that Key's current ownership
    # epoch, and that Key's side still keeps it.
    calculate :shown_to,
              :boolean,
              expr(
                ((from_token_id == ^arg(:token_id) and sent_in_current_epoch) or
                   (to_token_id == ^arg(:token_id) and received_in_current_epoch)) and
                  kept_for(token_id: ^arg(:token_id))
              ) do
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
    end

    # Whether Key `token_id`'s side of the conversation keeps the message.
    calculate :kept_for,
              :boolean,
              expr(
                if(conversation.key_a == ^arg(:token_id),
                  do: kept_by_key_a,
                  else: kept_by_key_b
                )
              ) do
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
    end

    calculate :kept_by_sender,
              :boolean,
              expr(
                if(conversation.key_a == from_token_id, do: kept_by_key_a, else: kept_by_key_b)
              )

    calculate :kept_by_recipient,
              :boolean,
              expr(if(conversation.key_a == to_token_id, do: kept_by_key_a, else: kept_by_key_b))

    # Whether a side keeps the message: it came after where that side last
    # cleared, and inside that side's auto-delete days.
    calculate :kept_by_key_a,
              :boolean,
              expr(
                seq > conversation.key_a_cleared_seq and
                  (is_nil(conversation.key_a_auto_delete_days) or
                     inserted_at >=
                       fragment(
                         "(now() AT TIME ZONE 'utc') - ? * interval '1 day'",
                         conversation.key_a_auto_delete_days
                       ))
              )

    calculate :kept_by_key_b,
              :boolean,
              expr(
                seq > conversation.key_b_cleared_seq and
                  (is_nil(conversation.key_b_auto_delete_days) or
                     inserted_at >=
                       fragment(
                         "(now() AT TIME ZONE 'utc') - ? * interval '1 day'",
                         conversation.key_b_auto_delete_days
                       ))
              )

    # Whether the sending Key still has the holder that sent it.
    calculate :sent_in_current_epoch,
              :boolean,
              expr(
                from_ownership_epoch ==
                  fragment(
                    "(SELECT max(epoch.ownership_epoch) FROM keyfleet_app.key_attachments AS epoch WHERE epoch.fleet_id = ? AND epoch.token_id = ?)",
                    fleet_id,
                    from_token_id
                  )
              )

    # Whether the receiving Key still has the holder it had when this arrived.
    calculate :received_in_current_epoch,
              :boolean,
              expr(
                to_ownership_epoch ==
                  fragment(
                    "(SELECT max(epoch.ownership_epoch) FROM keyfleet_app.key_attachments AS epoch WHERE epoch.fleet_id = ? AND epoch.token_id = ?)",
                    fleet_id,
                    to_token_id
                  )
              )

    # Whether the Key the message went to has blocked the Key that sent it.
    calculate :sender_blocked,
              :boolean,
              expr(
                fragment(
                  "EXISTS (SELECT 1 FROM keyfleet_app.dm_blocks AS b WHERE b.fleet_id = ? AND b.blocker_token_id = ? AND b.blocked_token_id = ?)",
                  fleet_id,
                  to_token_id,
                  from_token_id
                )
              )
  end

  identities do
    identity :unique_send_key, [
      :fleet_id,
      :from_token_id,
      :from_ownership_epoch,
      :idempotency_key
    ]
  end
end
