defmodule Regents.Patchbay.Forum.ThreadView do
  @moduledoc """
  One reader having opened one thread. A thread's view count is how many
  readers it has had, not how many times its page loaded: the reader is the
  signed-in profile, or the forum session the server issued the browser, so
  reloading, liking or replying never counts again.

  The table and its rows as patchbay.help keeps them. Patchbay's pages read
  them; nothing here writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Forum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("forum_thread_views")
    schema("patchbay_app")
    repo(Regents.Repo)

    references do
      reference(:report, index?: true)
    end
  end

  attributes do
    uuid_primary_key(:id)

    # Who read it: `profile:` or `session:` and an id.
    attribute(:viewer, :string, allow_nil?: false)

    create_timestamp(:inserted_at, public?: true)
  end

  relationships do
    belongs_to(:report, Regents.Patchbay.Forum.Report, allow_nil?: false, public?: true)
  end

  identities do
    identity(:report_viewer, [:report_id, :viewer])
  end

  actions do
    defaults([:read])
  end

  # Only reads are carried; any other action is refused until it comes with its
  # own policy.
  policies do
    # A thread's view count is public; no actor is required.
    policy action_type(:read) do
      authorize_if(always())
    end
  end
end
