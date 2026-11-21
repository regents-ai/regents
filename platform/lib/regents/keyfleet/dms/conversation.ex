defmodule Regents.Keyfleet.Dms.Conversation do
  @moduledoc """
  The one conversation between two Keys of a fleet, opened by the first message
  either sends the other. Its two Keys are kept lowest first (`key_a`,
  `key_b`), so a pair has exactly one.

  Each side keeps its own view of it. A Key's holder may clear it, which takes
  every message so far out of that Key's view (`:clear`, up to its side's
  `cleared_seq`), or have that Key's view drop messages older than 1, 7, 30 or
  90 days (`:set_auto_delete`, its side's `auto_delete_days`, nil to keep
  them). The other side's view is unchanged. A message leaves the database once
  neither side keeps it (`Regents.Keyfleet.Dms.Message`'s `:remove_expired`).

  A Key reads a conversation only while it holds a message of it that its
  holder may see (`Regents.Keyfleet.Dms.Message`'s `shown_to`), and its last message
  is the last of those: a Key's new holder finds none of the old holder's
  conversations until a new message arrives in one.
  """
  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Keyfleet.Dms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  @bigint 9_223_372_036_854_775_807
  @auto_delete_days [1, 7, 30, 90]
  # An inbox lists its most recent conversations, as many as a page shows.
  @inbox_page 100

  postgres do
    table "dm_conversations"
    schema("keyfleet_app")
    repo(Regents.Repo)

    check_constraints do
      check_constraint(:key_a, "dm_conversations_key_order", check: "key_a > 0 AND key_a < key_b")

      check_constraint(:key_a_auto_delete_days, "dm_conversations_key_a_auto_delete_days",
        check: "key_a_auto_delete_days IS NULL OR key_a_auto_delete_days IN (1, 7, 30, 90)"
      )

      check_constraint(:key_b_auto_delete_days, "dm_conversations_key_b_auto_delete_days",
        check: "key_b_auto_delete_days IS NULL OR key_b_auto_delete_days IN (1, 7, 30, 90)"
      )
    end

    custom_indexes do
      # The conversations of the Key on the higher side; the pair's identity
      # already reads the lower side's.
      index([:fleet_id, :key_b])
    end
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    # One Key's conversations, the newest message it may see first: its main
    # inbox, or with `blocked` those with the Keys it has blocked.
    read :inbox do
      argument :fleet_id, :string, allow_nil?: false
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :blocked, :boolean, allow_nil?: false, default: false

      validate Regents.Keyfleet.Graph.Validations.KnownFleet

      filter expr(
               fleet_id == ^arg(:fleet_id) and
                 (key_a == ^arg(:token_id) or key_b == ^arg(:token_id)) and
                 blocked_by(token_id: ^arg(:token_id)) == ^arg(:blocked) and
                 not is_nil(last_seq(token_id: ^arg(:token_id)))
             )

      prepare {Regents.Keyfleet.Dms.Preparations.LastShown, newest_first: true}
      prepare build(limit: @inbox_page)
    end

    # The conversation between two Keys, if they have one.
    read :between do
      get? true
      argument :fleet_id, :string, allow_nil?: false
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :other_token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]

      validate Regents.Keyfleet.Graph.Validations.KnownFleet

      filter expr(
               fleet_id == ^arg(:fleet_id) and
                 ((key_a == ^arg(:token_id) and key_b == ^arg(:other_token_id)) or
                    (key_a == ^arg(:other_token_id) and key_b == ^arg(:token_id))) and
                 not is_nil(last_seq(token_id: ^arg(:token_id)))
             )

      prepare Regents.Keyfleet.Dms.Preparations.LastShown
    end

    # Opened by the first message between two Keys, inside its sending
    # (`Regents.Keyfleet.Dms.Changes.SendMessage`); a later message meets the same row.
    create :open do
      public? false
      accept [:fleet_id, :key_a, :key_b]

      upsert? true
      upsert_identity :unique_pair
      upsert_fields [:updated_at]
    end

    # Key `token_id`'s view drops its messages older than `auto_delete_days`
    # (nil keeps them). Answers with that view's last message and days loaded.
    update :set_auto_delete do
      change Regents.Keyfleet.Agents.Changes.RecordAuthority
      require_atomic? false
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      accept []
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
      argument :auto_delete_days, :integer

      validate one_of(:auto_delete_days, @auto_delete_days),
        where: present(:auto_delete_days)

      change atomic_update(
               :key_a_auto_delete_days,
               expr(
                 if(key_a == ^arg(:token_id),
                   do: ^arg(:auto_delete_days),
                   else: key_a_auto_delete_days
                 )
               )
             )

      change atomic_update(
               :key_b_auto_delete_days,
               expr(
                 if(key_b == ^arg(:token_id),
                   do: ^arg(:auto_delete_days),
                   else: key_b_auto_delete_days
                 )
               )
             )

      change Regents.Keyfleet.Dms.Changes.LoadSide
    end

    # Takes every message so far out of Key `token_id`'s view, up to the
    # conversation's newest message; the other side keeps its own.
    update :clear do
      change Regents.Keyfleet.Agents.Changes.RecordAuthority
      require_atomic? false
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      accept []
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]

      change atomic_update(
               :key_a_cleared_seq,
               expr(
                 if(key_a == ^arg(:token_id),
                   do:
                     fragment(
                       "(SELECT coalesce(max(m.seq), 0) FROM keyfleet_app.dm_messages AS m WHERE m.conversation_id = ?)",
                       id
                     ),
                   else: key_a_cleared_seq
                 )
               )
             )

      change atomic_update(
               :key_b_cleared_seq,
               expr(
                 if(key_b == ^arg(:token_id),
                   do:
                     fragment(
                       "(SELECT coalesce(max(m.seq), 0) FROM keyfleet_app.dm_messages AS m WHERE m.conversation_id = ?)",
                       id
                     ),
                   else: key_b_cleared_seq
                 )
               )
             )
    end
  end

  # Delivered after a clearing commits, as `%Phoenix.Socket.Broadcast{}` on
  # `Regents.Keyfleet.Dms.inbox_topic/2` of the Key that cleared it only: "dm_deleted"
  # with `%{conversation_id}`.
  pub_sub do
    module Phoenix.PubSub
    name Regents.PubSub
    prefix "keyfleet:dms"
    broadcast_type :phoenix_broadcast

    publish :clear, [:fleet_id, :key_a],
      event: "dm_deleted",
      filter: &(&1.changeset.arguments.token_id == &1.data.key_a),
      transform: &%{conversation_id: &1.data.id}

    publish :clear, [:fleet_id, :key_b],
      event: "dm_deleted",
      filter: &(&1.changeset.arguments.token_id == &1.data.key_b),
      transform: &%{conversation_id: &1.data.id}
  end

  policies do
    policy action([:read, :open]) do
      authorize_if actor_attribute_equals(:role, :system)
    end

    policy action([:inbox, :between]) do
      authorize_if {Regents.Keyfleet.Dms.Checks.KeyHolder, keys: [:token_id]}
    end

    policy action([:set_auto_delete, :clear]) do
      forbid_unless expr(key_a == ^arg(:token_id) or key_b == ^arg(:token_id))
      authorize_if {Regents.Keyfleet.Dms.Checks.KeyHolder, keys: [:token_id]}
    end
  end

  attributes do
    attribute :acting_agent_wallet, :string, writable?: false
    attribute :beneficiary_privy_user_id, :string, writable?: false, sensitive?: true
    attribute :agent_pairing_id, :uuid, writable?: false

    uuid_primary_key :id

    attribute :key_a, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1, max: @bigint]

    attribute :key_b, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1, max: @bigint]

    # Each side's view: the last message it cleared, and how many days it
    # keeps messages for (nil keeps them).
    attribute :key_a_cleared_seq, :integer,
      allow_nil?: false,
      default: 0,
      constraints: [min: 0, max: @bigint]

    attribute :key_b_cleared_seq, :integer,
      allow_nil?: false,
      default: 0,
      constraints: [min: 0, max: @bigint]

    attribute :key_a_auto_delete_days, :integer, constraints: [min: 1, max: 90]
    attribute :key_b_auto_delete_days, :integer, constraints: [min: 1, max: 90]

    timestamps(public?: true)
  end

  relationships do
    belongs_to :fleet, Regents.Keyfleet.Fleets.Fleet do
      attribute_type :string
      allow_nil? false
      public? true
    end

    has_many :messages, Regents.Keyfleet.Dms.Message
  end

  calculations do
    # Where Key `token_id`'s side last cleared the conversation.
    calculate :cleared_seq,
              :integer,
              expr(if(key_a == ^arg(:token_id), do: key_a_cleared_seq, else: key_b_cleared_seq)) do
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
    end

    # How many days Key `token_id`'s side keeps messages for; nil keeps them.
    calculate :auto_delete_days,
              :integer,
              expr(
                if(key_a == ^arg(:token_id),
                  do: key_a_auto_delete_days,
                  else: key_b_auto_delete_days
                )
              ) do
      public? true
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
    end

    # The last message Key `token_id`, one side of the conversation, may see.
    # Read beside the conversation, which that Key was already allowed to
    # read; the messages are filtered to the ones its holder may see, so their
    # own read policy (system only) is not asked again.
    calculate :last_seq,
              :integer,
              expr(
                max(messages,
                  field: :seq,
                  query: [filter: shown_to(token_id: ^arg(:token_id))],
                  authorize?: false
                )
              ) do
      public? true
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
    end

    calculate :last_body,
              :string,
              expr(
                first(messages,
                  field: :body,
                  query: [filter: shown_to(token_id: ^arg(:token_id)), sort: [seq: :desc]],
                  authorize?: false
                )
              ) do
      public? true
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
    end

    calculate :last_from_token_id,
              :integer,
              expr(
                first(messages,
                  field: :from_token_id,
                  query: [filter: shown_to(token_id: ^arg(:token_id)), sort: [seq: :desc]],
                  authorize?: false
                )
              ) do
      public? true
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
    end

    calculate :last_at,
              :utc_datetime_usec,
              expr(
                first(messages,
                  field: :inserted_at,
                  query: [filter: shown_to(token_id: ^arg(:token_id)), sort: [seq: :desc]],
                  authorize?: false
                )
              ) do
      public? true
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
    end

    # Whether Key `token_id`, one side of the conversation, has blocked the
    # other side.
    calculate :blocked_by,
              :boolean,
              expr(
                fragment(
                  "EXISTS (SELECT 1 FROM keyfleet_app.dm_blocks AS b WHERE b.fleet_id = ? AND b.blocker_token_id = ? AND b.blocked_token_id = (CASE WHEN ? = ? THEN ? ELSE ? END))",
                  fleet_id,
                  ^arg(:token_id),
                  key_a,
                  ^arg(:token_id),
                  key_b,
                  key_a
                )
              ) do
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @bigint]
    end
  end

  identities do
    identity :unique_pair, [:fleet_id, :key_a, :key_b]
  end

  @doc "The days a conversation may keep its messages for, besides keeping them."
  def auto_delete_days, do: @auto_delete_days
end
