defmodule Regents.Patchbay.Forum.PostAddress do
  @moduledoc """
  A post's one address: `/patchbay/posts/<id>/<words>`, its id and then the
  words of its headline (`Regents.Patchbay.Forum.PostSummary.headline/1`): for
  a question or a report, the error it is about first, then its title; for any
  other thread, its title. So the address says what the post is about.

  The words are worked out each time, never stored. The id alone finds the
  post, so an address with other words after the id (or none) is answered
  with a permanent move to this one.

  An incident's discussion has one address of its own, the incident's page.
  """

  alias Regents.Patchbay.Forum.{PostSummary, Report, Site}

  @limit 80

  @doc "The post's address on this site, as a path."
  @spec path(map()) :: String.t()
  def path(%{incident: incident}) when is_binary(incident),
    do: "/patchbay/incidents/" <> incident

  def path(post), do: "/patchbay/posts/#{post.id}/#{post |> PostSummary.headline() |> slug()}"

  @doc "The post's address with a query, such as a page of its replies."
  @spec path(map(), map() | keyword()) :: String.t()
  def path(post, query) when query in [%{}, []], do: path(post)
  def path(post, query), do: path(post) <> "?" <> URI.encode_query(query)

  @doc "The post's full public URL on this site."
  @spec url(map()) :: String.t()
  def url(post), do: Regents.Patchbay.site_url() <> path(post)

  @doc "A read of reports with only what their addresses are made from."
  @spec report_query() :: Ash.Query.t()
  def report_query do
    Report
    |> Ash.Query.select([
      :id,
      :thread_kind,
      :title,
      :note,
      :tool_names,
      :body_markdown,
      :site_id,
      :incident
    ])
    |> Ash.Query.load(site: Ash.Query.select(Site, [:id, :display_name, :origin]))
  end

  @doc """
  The words of an address: lowercase ASCII letters, digits and underscores
  (so `no_touch_id` stays whole), a hyphen between words, at most #{@limit}
  characters and cut between words. Letters with accents lose them, and
  apostrophes join their word (`fleet's` is `fleets`). Text with no such
  words gives `post`.
  """
  @spec slug(String.t()) :: String.t()
  def slug(text) do
    text
    |> :unicode.characters_to_nfkd_binary()
    |> String.replace(~r/[\p{Mn}'’]/u, "")
    |> String.downcase()
    |> String.split(~r/[^a-z0-9_]+/, trim: true)
    |> Enum.filter(&(&1 =~ ~r/[a-z0-9]/))
    |> within(@limit)
    |> case do
      "" -> "post"
      words -> words
    end
  end

  # As many whole words as fit; a first word longer than the limit is cut.
  defp within([], _limit), do: ""

  defp within([first | rest], limit) do
    Enum.reduce_while(rest, binary_part(first, 0, min(byte_size(first), limit)), fn word, acc ->
      joined = acc <> "-" <> word
      if byte_size(joined) <= limit, do: {:cont, joined}, else: {:halt, acc}
    end)
  end
end
