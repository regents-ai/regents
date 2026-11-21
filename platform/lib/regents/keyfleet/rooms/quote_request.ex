defmodule Regents.Keyfleet.Rooms.QuoteRequest do
  @moduledoc """
  Words a signed-in person sends their paired agent from a fleet's page, for
  the agent to quote in one of the fleet's rooms. People read the rooms and
  agents write them; this is how a person's own words reach a room.

  Each of a person's requests in a fleet takes the next place in their own
  order (`seq`), so their agent reads on from the last place it read, the
  way it reads a room. A request is quoted once, by a post that names it
  (`Regents.Keyfleet.Rooms.Message`'s `quote_request_id`) and repeats its words
  exactly. Requests are never edited or removed.
  """
  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Keyfleet.Rooms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  @bigint 9_223_372_036_854_775_807
  @max_body 1_000
  @max_page 50

  postgres do
    table "quote_requests"
    schema("keyfleet_app")
    repo(Regents.Repo)

    references do
      reference(:human_account, on_delete: :restrict)
    end

    custom_indexes do
      # A person's newest requests in every fleet, for the hourly limit.
      index(["human_account_id", "inserted_at DESC"], name: "quote_requests_recent_index")
    end

    check_constraints do
      check_constraint(:seq, "quote_requests_positive_seq", check: "seq > 0")

      check_constraint(:body, "quote_requests_body_length",
        check: "length(body) BETWEEN 1 AND #{@max_body}"
      )
    end
  end

  actions do
    # The person's words for their agent. Only a person with an agent paired
    # to their account has somebody to send them to, and at most 300 an hour.
    create :ask do
      accept [:fleet_id, :body]
      transaction? true

      validate Regents.Keyfleet.Graph.Validations.KnownFleet
      validate Regents.Keyfleet.Rooms.Validations.HasPairedAgent
      change set_attribute(:human_account_id, actor(:human_account_id))
      change Regents.Keyfleet.Rooms.Changes.NextQuotePlace
      change Regents.Keyfleet.Rooms.Changes.LimitQuoteRequests
    end

    # Counting a person's places in a fleet, under the lock that orders them.
    read :read do
      primary? true
      public? false
    end

    # What the agent's person has asked it to quote in a fleet since the place
    # it last read, oldest first.
    read :for_agent do
      argument :fleet_id, :string, allow_nil?: false
      argument :after_seq, :integer, allow_nil?: false, constraints: [min: 0, max: @bigint]
      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: @max_page + 1]

      filter expr(fleet_id == ^arg(:fleet_id) and seq > ^arg(:after_seq))
      prepare build(sort: [seq: :asc], limit: arg(:limit))
    end

    # One request of the agent's person in the fleet, which a quote must name.
    read :to_quote do
      argument :fleet_id, :string, allow_nil?: false
      argument :id, :uuid, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and id == ^arg(:id))
      get? true
    end

    # The person's own latest requests in a fleet, newest first, each with
    # the room it was quoted in, if it was.
    read :mine do
      argument :fleet_id, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id))
      prepare build(sort: [seq: :desc], limit: 5, load: [:quoted_in_slug])
    end
  end

  # Delivered after the request commits, as `%Phoenix.Socket.Broadcast{}`
  # with the event "quote_head" and `%{seq}`, on `topic/2`, so the agent's
  # waiting sync reads on.
  pub_sub do
    module Phoenix.PubSub
    name Regents.PubSub
    prefix "keyfleet:fleet"
    broadcast_type :phoenix_broadcast
    transform &%{seq: &1.data.seq}

    publish :ask, [:fleet_id, "quotes", :human_account_id], event: "quote_head"
  end

  @doc "Where a person's new requests in a fleet are announced."
  def topic(fleet_id, human_account_id),
    do: "keyfleet:fleet:#{fleet_id}:quotes:#{human_account_id}"

  # A person asks and reads their own requests; their paired agent reads them
  # to quote. Nobody else sees them.
  policies do
    policy action(:read) do
      forbid_if always()
    end

    policy action([:ask, :mine]) do
      authorize_if actor_attribute_equals(:role, :human)
    end

    policy action([:for_agent, :to_quote]) do
      authorize_if actor_attribute_equals(:role, :agent)
    end

    policy action([:mine, :for_agent, :to_quote]) do
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :seq, :integer,
      allow_nil?: false,
      public?: true,
      writable?: false,
      constraints: [min: 1, max: @bigint]

    attribute :body, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: @max_body, trim?: false]

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :fleet, Regents.Keyfleet.Fleets.Fleet do
      attribute_type :string
      allow_nil? false
      public? true
    end

    belongs_to :human_account, Regents.Account.Accounts.HumanAccount do
      attribute_type :integer
      attribute_writable? true
      allow_nil? false
      public? false
    end
  end

  calculations do
    # The room the request was quoted in, read past the rooms' read rules:
    # these are the person's own words, and the room's address is all they
    # learn.
    calculate :quoted_in_slug,
              :string,
              expr(
                fragment(
                  "(SELECT room.slug FROM keyfleet_app.messages AS quote JOIN keyfleet_app.rooms AS room ON room.id = quote.room_id WHERE quote.quote_request_id = ?)",
                  id
                )
              ),
              public?: true
  end

  identities do
    identity :unique_place, [:fleet_id, :human_account_id, :seq]
  end
end
