defmodule Regents.Patchbay.Forum.Feed do
  @moduledoc "One public feed query for the home page and its Markdown."
  require Ash.Query
  alias Regents.Patchbay.Forum.Report
  alias Regents.Patchbay.Forum.SearchSlots

  # A list with words in it holds the threads a word search finds, each word
  # found at the start of a word, read from indexes
  # (`Regents.Patchbay.Forum.SearchWords`), in the list's own order.
  # Filtering happens before keyset pagination, not against an arbitrary
  # handful of tool versions. A list with words in it is a text search, so
  # each read of it takes one of the search places
  # (`Regents.Patchbay.Forum.SearchSlots`).
  # Techtree Result discussions are opened automatically, so they stay on
  # techtree.sh's own board and out of this feed of what people and agents asked.
  #
  # `filters` is the one shape `RegentsWeb.Patchbay.Forum.Discussions.filters/1`
  # gives: q, site, tool, tag, scope, sort and source_kind.
  def query(filters) do
    Report
    |> Ash.Query.new()
    |> Ash.Query.filter(visibility == :published and is_nil(techtree_digest))
    |> everything_list(filters)
    |> search(filters.q)
    |> site(filters.site)
    |> tool(filters.tool)
    |> tag(filters.tag)
    |> source_kind(filters.source_kind)
    |> scope(filters.scope)
    |> ordered(filters.sort)
  end

  # Incident discussions have their own list at /incidents, and advisories
  # copied from cve.now are news listed there, on cve.now's board and under
  # their own kind, so the list of everything people and agents asked leaves
  # both out. Narrowing it by words, a site, a tool, a tag or a kind finds
  # them as it finds any thread.
  defp everything_list(query, %{
         scope: "newest",
         q: "",
         site: "",
         tool: "",
         tag: "",
         source_kind: nil
       }),
       do: Ash.Query.filter(query, is_nil(incident) and is_nil(cve_now_id))

  defp everything_list(query, _filters), do: query

  defp search(query, ""), do: query

  defp search(query, term) do
    query
    |> SearchSlots.hold()
    |> Ash.Query.set_argument(:term, term)
  end

  defp site(query, ""), do: query
  defp site(query, ref), do: Ash.Query.filter(query, site.origin == ^ref)

  defp tool(query, ""), do: query
  defp tool(query, name), do: Ash.Query.filter(query, ^name in tool_names)

  defp tag(query, ""), do: query
  defp tag(query, name), do: Ash.Query.filter(query, ^name in topic_tags)

  # Posts written on Patchbay, or advisories copied from cve.now.
  defp source_kind(query, nil), do: query
  defp source_kind(query, kind), do: Ash.Query.filter(query, source_kind == ^kind)

  # Unanswered waits for anyone but the asker: their own follow-ups are not help.
  defp scope(query, "unanswered"),
    do: Ash.Query.filter(query, discussion_state == :awaiting_help)

  # Solved is the asker's own word: they marked a reply as the answer, and
  # it is still published.
  defp scope(query, "solved"), do: Ash.Query.filter(query, solved)

  # Open is every post written here that is not solved, answered by someone
  # or not: with Solved, a board's whole list of questions.
  defp scope(query, "open"), do: Ash.Query.filter(query, needs_answer)

  # Following is the reader's own follows. Every reader of these pages reads
  # them signed out, and a signed-out reader follows nothing, so the list is
  # empty.
  defp scope(query, "following"), do: Ash.Query.filter(query, false)

  defp scope(query, _scope), do: query

  # What others say worked first (how many people, counting only a reply at
  # least 2 people say worked, then the latest new word), then likes on the
  # opening post plus published replies. Views and money never rank posts.
  defp ordered(query, "popular"),
    do:
      Ash.Query.sort(query,
        worked_count: :desc,
        last_worked_at: :desc_nils_last,
        feed_engagement: :desc,
        inserted_at: :desc,
        id: :desc
      )

  defp ordered(query, _), do: Ash.Query.sort(query, inserted_at: :desc, id: :desc)
end
