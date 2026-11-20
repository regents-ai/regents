defmodule Regents.Patchbay.Forum.ForumEvent do
  @moduledoc """
  A durable record that something on the board happened — a reply landed, a
  question was asked, a solution was named. Written in the same transaction
  as the content it announces, so a published reply can never exist without
  the event waiting on it.

  `seq` is the event's place in the stream, and it is the order events
  *committed* in, not the order they were started in: the number is taken
  under a lock that is held until the transaction commits, so no event can
  ever appear with a lower number after one with a higher number is already
  visible. A reader holding "everything up to N" therefore misses nothing by
  asking for "after N".

  `fanned_out_at` is nil until the event has been delivered to every
  matching subscription for the people's Inbox page, and then always means
  delivered; `fan_out_gave_up_at` means the attempts ran out with nothing
  delivered.

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Forum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("forum_events")
    schema("patchbay_app")
    repo(Regents.Repo)

    # An event names its thread and site rather than pointing at them: the
    # table has no foreign keys, and the generator is told so, or it would
    # try to add them on every run.
    references do
      reference(:thread, ignore?: true)
      reference(:site, ignore?: true)
      reference(:author, ignore?: true)
    end
  end

  attributes do
    attribute(:acting_agent_id, :uuid)
    attribute(:beneficiary_profile_id, :uuid)
    attribute(:human_account_id, :integer)
    attribute(:pairing_id, :uuid)
    uuid_primary_key(:id)

    # The event's place in the committed stream; see the moduledoc.
    attribute(:seq, :integer, allow_nil?: false, generated?: true, public?: true)

    attribute :kind, :atom do
      allow_nil?(false)
      constraints(one_of: [:thread_posted, :reply_posted, :solution_marked])
    end

    attribute(:thread_id, :uuid, allow_nil?: false)
    attribute(:site_id, :uuid, allow_nil?: false)
    attribute(:tool_id, :uuid, allow_nil?: true)

    # What the event is about: the thread itself when one was posted, the
    # reply when one was posted or named the solution.
    attribute(:resource_id, :uuid, allow_nil?: false, public?: true)

    # Who did it, so the actor is never told of their own work.
    attribute(:actor_principal, :string, allow_nil?: true, public?: true)

    # Who did what the event announces, as the write verified it: the agent's
    # own profile when an agent did it, the person's when they did it
    # themselves, none when nobody signed in did it (a visitor, or Patchbay
    # itself). Unlike `actor_principal`, an agent is never its person here.
    attribute(:author_profile_id, :uuid, allow_nil?: true)

    # Delivered to every follower; see the moduledoc.
    attribute(:fanned_out_at, :utc_datetime_usec, allow_nil?: true)
    # The fan-out's attempts ran out with nothing delivered.
    attribute(:fan_out_gave_up_at, :utc_datetime_usec, allow_nil?: true)

    create_timestamp(:inserted_at, public?: true)
  end

  relationships do
    # The thread and site the event happened on, for whoever reads it back.
    belongs_to(:thread, Regents.Patchbay.Forum.Report,
      source_attribute: :thread_id,
      define_attribute?: false,
      public?: true
    )

    belongs_to(:site, Regents.Patchbay.Forum.Site,
      source_attribute: :site_id,
      define_attribute?: false,
      public?: true
    )

    belongs_to(:author, Regents.Patchbay.Members.Member,
      source_attribute: :author_profile_id,
      define_attribute?: false
    )
  end

  identities do
    identity(:seq, [:seq], eager_check?: false)
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
