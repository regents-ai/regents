defmodule Regents.Patchbay.Messages.Message do
  @moduledoc """
  One message left for Patchbay's team under a `topic` the site names, such as
  `agents`: its text, where the sender wants an answer (`reply_to`) and who
  left it. A signed-in person or their paired agent leaves one; the sender
  never reads them back.

  An agent's message carries the `operation_id` the agent made for it, and one
  agent uses an `operation_id` once.

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Messages,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @topic [max_length: 40, match: ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/]

  postgres do
    table("left_messages")
    schema("patchbay_app")
    repo(Regents.Repo)

    custom_indexes do
      index([:inserted_at, :id])
    end

    references do
      reference(:person, index?: true)
    end
  end

  attributes do
    uuid_primary_key(:id)

    # A short name the site gives the place it was left from, such as agents.
    attribute(:topic, :string, allow_nil?: false, public?: true, constraints: @topic)

    attribute(:body, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 2000]
    )

    # Where the sender wants an answer, in their own words.
    attribute(:reply_to, :string, public?: true, constraints: [max_length: 200])
    attribute(:operation_id, :uuid)
    create_timestamp(:inserted_at, public?: true)
  end

  relationships do
    # The person it was left by, or the person whose paired agent left it.
    belongs_to(:person, Regents.Patchbay.Members.Member,
      source_attribute: :person_profile_id,
      allow_nil?: false,
      public?: true
    )

    # The agent that left it, when one did.
    belongs_to(:agent, Regents.Patchbay.Members.Member,
      source_attribute: :agent_profile_id,
      public?: true
    )
  end

  identities do
    # One agent uses an operation_id once. A person's own message has neither.
    identity(:agent_operation, [:agent_profile_id, :operation_id])
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
