defmodule Regents.Messages.Message do
  @moduledoc """
  One message left for the site's team under a `topic` the site names, such as
  `agents`: its text, where the sender wants an answer (`reply_to`) and who left
  it. A signed-in person or a paired agent leaves one, a few an hour at most,
  for each person and each network (`SpendAllowance`). The sender is the actor,
  never an input (`SetSender`). Only the site's admins read messages
  (`Regents.Checks.Admin`); the sender gets a receipt, `receipt/1`, and never
  reads them back.
  """

  use Ash.Resource,
    domain: Regents.Messages,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Messages.Message.{AgentLeave, SetSender, SpendAllowance}

  @topic [max_length: 40, match: ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/]
  @shown_text "Use letters, numbers and marks you can see."

  postgres do
    table "left_messages"
    repo(Regents.Repo)

    custom_indexes do
      index([:inserted_at, :id])
    end
  end

  attributes do
    uuid_primary_key :id
    # A short name the site gives the place it was left from, such as agents.
    attribute :topic, :string, allow_nil?: false, public?: true, constraints: @topic
    attribute :body, :string, allow_nil?: false, public?: true, constraints: [max_length: 2000]
    # Where the sender wants an answer, in their own words.
    attribute :reply_to, :string, public?: true, constraints: [max_length: 200]
    # The person's name when it was left, as their own Account page shows it.
    attribute :sender_name, :string, allow_nil?: false, public?: true
    # The paired agent that left it, if one did, and the operation_id it sent.
    attribute :agent_wallet_address, :string, public?: true
    attribute :operation_id, :uuid
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    # The person it was left by, or the person whose paired agent left it.
    belongs_to :human_account, Regents.Accounts.HumanAccount do
      attribute_type :integer
      allow_nil? false
    end
  end

  identities do
    # An agent's operation_id names one message.
    identity :agent_operation, [:agent_wallet_address, :operation_id]
  end

  actions do
    defaults [:read]

    # The team's inbox, newest first, a page at a time.
    read :newest do
      prepare build(sort: [inserted_at: :desc, id: :desc])
      pagination keyset?: true, default_limit: 50
    end

    read :by_operation do
      get_by [:agent_wallet_address, :operation_id]
    end

    create :leave do
      accept [:topic, :body, :reply_to]
      change SetSender
      validate match(:body, RegentFormat.Text.pattern()), message: @shown_text
      validate match(:reply_to, RegentFormat.Name.pattern()), message: @shown_text
      change SpendAllowance
    end

    # A paired agent's message, its operation_id answered once (`AgentLeave`).
    action :agent_leave, :map do
      argument :topic, :string,
        allow_nil?: false,
        constraints: @topic,
        description:
          "The topic the site gives, such as agents: lowercase letters, numbers and hyphens, up to 40."

      argument :body, :string,
        allow_nil?: false,
        constraints: [max_length: 2000],
        description: "The message, 1 to 2,000 characters."

      argument :reply_to, :string,
        constraints: [max_length: 200],
        description:
          "Where you want an answer, up to 200 characters, such as an email address or a profile. Leave it out for none."

      argument :operation_id, :uuid,
        allow_nil?: false,
        description:
          "A UUID you make for this message. Keep it when retrying: a retry answers the first message, and a UUID already used for another message is refused."

      run AgentLeave
    end
  end

  policies do
    policy action(:leave) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if actor_attribute_equals(:role, :agent)
    end

    policy action(:agent_leave) do
      authorize_if actor_attribute_equals(:role, :agent)
    end

    # The site's admins on their team page; the site itself when it answers a
    # retried message with its receipt (`AgentLeave`).
    policy action_type(:read) do
      authorize_if Regents.Checks.Admin
      authorize_if Regents.Checks.SystemActor
    end
  end

  @doc "What the sender is told once a message is left: its id, topic and time."
  def receipt(message),
    do: %{id: message.id, topic: message.topic, inserted_at: message.inserted_at}
end
