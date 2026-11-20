defmodule Regents.Patchbay.Forum.AnswerUse do
  @moduledoc """
  A participant's own report of what happened when they used an answer:
  `worked`, `did_not_work`, or `not_tried`.

  Self-reported, labeled so — a use report says what its writer claims, never
  that anyone verified it. Idempotent on (reply, principal, task token): the
  same use reported twice is one use, and a later report corrects the earlier.
  The reply's own author reporting on their own answer is recorded as
  `same_author` so downstream tallies can leave it out.

  The table and its rows as patchbay.help keeps them. Patchbay's pages read
  them; nothing here writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Forum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("forum_answer_uses")
    schema("patchbay_app")
    repo(Regents.Repo)
  end

  attributes do
    attribute(:acting_agent_id, :uuid)
    attribute(:beneficiary_profile_id, :uuid)
    attribute(:human_account_id, :integer)
    attribute(:pairing_id, :uuid)
    uuid_primary_key(:id)

    attribute :outcome, :atom do
      allow_nil?(false)
      constraints(one_of: [:worked, :did_not_work, :not_tried])
      public?(true)
    end

    attribute(:task_token, :string, allow_nil?: false, public?: true)
    attribute(:note, :string, allow_nil?: true, public?: true)
    attribute(:same_author, :boolean, allow_nil?: false, default: false, public?: true)
    attribute(:applicable_tool_version, :string, allow_nil?: true, public?: true)

    create_timestamp(:inserted_at, public?: true)
    update_timestamp(:updated_at, public?: true)

    attribute(:principal, :string, allow_nil?: false)
  end

  relationships do
    belongs_to(:reply, Regents.Patchbay.Forum.Reply, allow_nil?: false, public?: true)
  end

  identities do
    identity(:principal_task, [:reply_id, :principal, :task_token])
  end

  actions do
    defaults([:read])
  end

  # Only reads are carried; any other action is refused until it comes with its
  # own policy.
  policies do
    # Reads of self-reported tallies are public.
    policy action_type(:read) do
      authorize_if(always())
    end
  end
end
