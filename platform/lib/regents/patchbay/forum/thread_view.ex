defmodule Regents.Patchbay.Forum.ThreadView do
  @moduledoc """
  One reader having opened one thread. A thread's view count is how many
  readers it has had, not how many times its page loaded: the reader is the
  signed-in profile, or the forum session the server issued the browser, so
  reloading, liking or replying never counts again.

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
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

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
