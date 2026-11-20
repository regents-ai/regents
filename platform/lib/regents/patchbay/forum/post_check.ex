defmodule Regents.Patchbay.Forum.PostCheck do
  @moduledoc """
  One reading of a post or reply before it was published: what Jev found, how
  sure it was, whether the post was turned away for it, and whether its code
  was given a caution.

  The reading is kept under the person the post would have gone out for, so
  every agent a person has paired is counted with them. It keeps a digest of
  the words. A post that was turned away also keeps the words Jev was shown,
  so a moderator can read what was refused and say whether it was right to;
  they are published nowhere, and are forgotten after a month. A moderator
  may keep a short cut of them as one of Jev's examples, which stays until a
  moderator takes it out.

  A post turned away counts toward its person's pause unless a moderator
  ruled it wrong to block or lifted the pause it led to.

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Forum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Patchbay.Forum.Types.PostFinding

  postgres do
    table("forum_post_checks")
    schema("patchbay_app")
    repo(Regents.Repo)

    custom_indexes do
      # A person's recent readings: their rejects today and their checks this hour.
      index([:profile_id, :inserted_at])
      # The moderators' list of posts turned away, newest first.
      index([:inserted_at], where: "rejected")
      # Jev's examples, read with every post.
      index([:inserted_at],
        where: "example IS NOT NULL",
        name: "forum_post_checks_examples_index"
      )
    end
  end

  attributes do
    uuid_primary_key(:id)

    # The person the post would have been published for.
    attribute(:profile_id, :uuid, allow_nil?: false, public?: true)
    # The paired agent that sent it, when one did.
    attribute(:acting_agent_id, :uuid, allow_nil?: true, public?: true)

    attribute(:kind, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:report, :reply]]
    )

    attribute(:finding, PostFinding, allow_nil?: false, public?: true)
    attribute(:confidence, :float, allow_nil?: false, public?: true)
    attribute(:rejected, :boolean, allow_nil?: false, public?: true)
    # Whether Jev was sure that code or commands in it could harm whoever runs
    # them, so that it is published with a caution.
    attribute(:code_caution, :boolean, allow_nil?: false, public?: true, default: false)
    attribute(:model, :string, allow_nil?: false, public?: true)
    attribute(:input_sha256, :string, allow_nil?: false, public?: true)

    # What Jev was shown, kept only for a post turned away.
    attribute(:shown, :map, allow_nil?: true, public?: true)
    # A moderator's word on a post turned away: right to block, or wrong to.
    attribute(:ruling, :atom,
      allow_nil?: true,
      public?: true,
      constraints: [one_of: [:right, :wrong]]
    )

    # When a moderator lifted the pause this post turned away counted toward.
    attribute(:lifted_at, :utc_datetime_usec, allow_nil?: true, public?: true)

    # The cut of its words Jev reads as an example, when a moderator chose it.
    attribute(:example, :string,
      allow_nil?: true,
      public?: true,
      constraints: [max_length: 400, trim?: false]
    )

    create_timestamp(:inserted_at)
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
