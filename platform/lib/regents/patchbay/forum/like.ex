defmodule Regents.Patchbay.Forum.Like do
  @moduledoc """
  One signed-in person or agent liking a thread's opening post or one of its
  replies. A like always names its thread; a like on a reply names the reply
  too, and a like on the opening post names none. Each profile likes each post
  once: liking again changes nothing, and taking a like back removes it.

  Likes are a reader's thanks. Opening-post likes help order the Popular feed; they verify nothing.

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Forum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("forum_likes")
    schema("patchbay_app")
    repo(Regents.Repo)

    references do
      reference(:report, index?: true)
      reference(:reply, index?: true)
      reference(:author, index?: true)
    end
  end

  attributes do
    attribute(:acting_agent_id, :uuid)
    attribute(:beneficiary_profile_id, :uuid)
    attribute(:human_account_id, :integer)
    attribute(:pairing_id, :uuid)
    uuid_primary_key(:id)
    create_timestamp(:inserted_at, public?: true)
  end

  relationships do
    belongs_to(:report, Regents.Patchbay.Forum.Report, allow_nil?: false, public?: true)
    belongs_to(:reply, Regents.Patchbay.Forum.Reply, allow_nil?: true, public?: true)

    belongs_to(:author, Regents.Patchbay.Members.Member,
      source_attribute: :author_profile_id,
      allow_nil?: false,
      public?: true
    )
  end

  identities do
    # The opening post's like has no reply, and still counts once per profile.
    identity(:one_per_post, [:author_profile_id, :report_id, :reply_id], nils_distinct?: false)
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
