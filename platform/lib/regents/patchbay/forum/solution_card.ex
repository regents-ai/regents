defmodule Regents.Patchbay.Forum.SolutionCard do
  @moduledoc """
  The reusable, source-linked form of an answer a thread produced: what the
  problem was, who it applies to, the proposed steps, and the caveats — with a
  digest of the reply it was distilled from so the card is pinned to its
  source, and a status so a redacted source takes its card down with it.

  Cards are derived records: the asker's selection of a reply creates one as
  a summary, always attributed as a summary, never as independently verified.

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Forum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("forum_solution_cards")
    schema("patchbay_app")
    repo(Regents.Repo)

    custom_indexes do
      # A search of the cards reads this instead of every card.
      index(
        [
          "to_tsvector('english'::regconfig, coalesce(problem_summary, '') || ' ' || coalesce(proposed_steps, '') || ' ' || coalesce(caveats, ''))"
        ],
        name: "forum_solution_cards_search_words_index",
        using: "GIN",
        concurrently: true
      )
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:problem_summary, :string, allow_nil?: false, public?: true)
    attribute(:applicability, :string, allow_nil?: true, public?: true)
    attribute(:proposed_steps, :string, allow_nil?: false, public?: true)
    attribute(:caveats, :string, allow_nil?: true, public?: true)

    # What the card was distilled from, pinned by digest so a changed or
    # removed source cannot silently keep its card.
    attribute(:source_digest, :string, allow_nil?: false, public?: true)
    attribute(:source_author_profile_id, :uuid, allow_nil?: true, public?: true)

    attribute :status, :atom do
      allow_nil?(false)
      constraints(one_of: [:published, :invalidated])
      default(:published)
      public?(true)
    end

    attribute(:reviewed_by_profile_id, :uuid, allow_nil?: true, public?: true)
    attribute(:reviewed_at, :utc_datetime_usec, allow_nil?: true, public?: true)

    create_timestamp(:inserted_at, public?: true)
    update_timestamp(:updated_at, public?: true)
  end

  relationships do
    belongs_to(:thread, Regents.Patchbay.Forum.Report, allow_nil?: false, public?: true)
    belongs_to(:source_reply, Regents.Patchbay.Forum.Reply, allow_nil?: false, public?: true)
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
