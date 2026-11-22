defmodule Regents.Patchbay.Forum.ThreadView do
  @moduledoc """
  One reader having opened one thread. A thread's view count is how many
  readers it has had, not how many times its page loaded: the reader is the
  signed-in profile, or the forum session the server issued the browser, so
  reloading, liking or replying never counts again.

  The table and its rows as patchbay.help keeps them. A thread's page writes
  one (`:record`) when a browser that already holds its forum session opens
  it again, except where the site only reads (`Regents.read_only?/0`).
  """

  require Ash.Query

  alias Regents.Patchbay.Forum.Report

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

    create :record do
      description("""
      Records that one browser's forum session opened one published thread;
      opening it again records nothing. A thread that is held out of sight and
      an id that names no thread are refused alike.
      """)

      accept([:report_id])
      argument(:session_id, :uuid, allow_nil?: false)
      upsert?(true)
      upsert_identity(:report_viewer)
      upsert_fields([])

      validate(
        fn changeset, _context ->
          report_id = Ash.Changeset.get_attribute(changeset, :report_id)

          case Report
               |> Ash.Query.filter(id == ^report_id and visibility == :published)
               |> Ash.exists() do
            {:ok, true} -> :ok
            {:ok, false} -> {:error, field: :report_id, message: "names no published thread"}
            {:error, failure} -> {:error, failure}
          end
        end,
        only_when_valid?: true
      )

      change(
        fn changeset, _context ->
          session_id = Ash.Changeset.get_argument(changeset, :session_id)
          Ash.Changeset.force_change_attribute(changeset, :viewer, "session:" <> session_id)
        end,
        only_when_valid?: true
      )
    end
  end

  policies do
    # A view's viewer comes from a browser's forum session, so nobody reads
    # a view: a thread's count (`Report`'s `view_count`) counts them without
    # asking this read.
    policy action_type(:read) do
      forbid_if(always())
    end

    # The viewer is built here from the browser's forum session, which the
    # server issued it; no caller names a viewer, so recording a view needs
    # no actor.
    policy action(:record) do
      authorize_if(always())
    end
  end
end
