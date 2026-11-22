defmodule RegentsWeb.Keyfleet.AtlasPage do
  @moduledoc """
  A fleet's Atlas, read for its page (`RegentsWeb.Keyfleet.AtlasLive`) and for its
  agents (`RegentsWeb.Keyfleet.AgentTools.Workspace.Atlas`) from the three levels of
  `Regents.Keyfleet.Atlas`, as whoever reads it (`read_as`: `:actor` and `:context`,
  `Regents.Keyfleet.Access.context/3`), so only the fleet's members read anything.
  Every view of the page reads through here and nothing else.

  ## Windows and buckets

  A window is one calendar bucket of a span (`window/2`): a day, a week, a
  month or a year, in UTC. A window is read by buckets of a shorter span
  (`bucket/1` names the one the List and an agent use unless told).

  ## What each read answers

    * `rows/3`: the fleet's projects with any work counted, busiest first,
      each `%{project:, title:, changes:}`.
    * `swarm/6`: for each bucket of a span from `from` up to `to`, the
      changes, things and Keys of `Regents.Keyfleet.Atlas`'s swarm, of any `:source`
      and `:project`, split `:by` project or kind.
    * `totals/4` and `projects/4`: one window's changes, things changed and
      Keys at work, for the whole fleet and for each project.
    * `most_active/4` and `newest/4`: a page of one window's things
      (`thing()`), with `:after` for the page that follows, nil after the last.

  A thing's `path` is its own page: an item's page in the workspace, opened
  in place (`live?`), or the notebook itself on the fleet's notebook host.
  """

  alias Regents.Keyfleet.{Atlas, Notebooks, Projects}
  alias Regents.Keyfleet.Atlas.{Source, Span}
  alias RegentsWeb.Keyfleet.WorkspacePage

  import Regents.Keyfleet.Fleets.Rules, only: [grouped: 1]

  @windows [:day, :week, :month, :year]
  @buckets %{day: :hour, week: :day, month: :day, year: :week}

  # As far back as the rows look for the projects with work counted.
  @years 20

  @type window :: :day | :week | :month | :year
  @type thing :: %{
          id: String.t(),
          kind: String.t(),
          what: String.t(),
          project: String.t(),
          title: String.t(),
          key: pos_integer() | nil,
          who: String.t() | nil,
          at: DateTime.t(),
          changes: pos_integer(),
          actors: non_neg_integer(),
          path: String.t(),
          live?: boolean()
        }

  @doc "The windows a reader chooses between, shortest first."
  def windows, do: @windows

  @doc "The bucket a window is read by unless another is asked for."
  def bucket(window) when window in @windows, do: @buckets[window]

  @doc "The window of `span` holding `at`, as `{start, end}`."
  def window(span, %DateTime{} = at) do
    start = Span.start(span, at)
    {start, Span.next(span, start)}
  end

  @doc "The fleet's projects with work counted, busiest first, each with its title."
  def rows(fleet_id, source, read_as) do
    {:ok, now} = DateTime.now("Etc/UTC")
    {from, _} = window(:year, DateTime.add(now, -@years * 366, :day))
    {_, to} = window(:year, now)

    fleet_id
    |> Atlas.swarm!(:year, from, to, %{source: source, by: [:project]}, read_as)
    |> Enum.group_by(& &1.project, & &1.changes)
    |> Enum.map(fn {project, changes} -> %{project: project, changes: Enum.sum(changes)} end)
    |> titled(fleet_id)
    |> Enum.sort_by(&{-&1.changes, &1.project})
  end

  # Each project's counts with its title. A project deleted since its work
  # was read, whose counts go with it, is left out.
  defp titled(counts, fleet_id) do
    titles =
      fleet_id
      |> Projects.project_titles!(authorize?: false)
      |> Map.new(&{&1.name, &1.title})

    for %{project: project} = count <- counts,
        title = titles[project],
        do: Map.put(count, :title, title)
  end

  @doc "The swarm's buckets of `span` from `from` up to `to`, of `filter`'s `:source`, `:project` and `:by`."
  def swarm(fleet_id, span, from, to, filter, read_as),
    do: Atlas.swarm!(fleet_id, span, from, to, filter, read_as)

  @doc "The window's changes, things changed and Keys at work, for the whole fleet."
  def totals(fleet_id, span, at, source, read_as) do
    {from, to} = window(span, at)

    case Atlas.swarm!(fleet_id, span, from, to, %{source: source, by: []}, read_as) do
      [cell] -> Map.take(cell, [:changes, :things, :actors])
      [] -> %{changes: 0, things: 0, actors: 0}
    end
  end

  @doc "Each project's changes, things and Keys in the window, busiest first, with its title."
  def projects(fleet_id, span, at, source, read_as) do
    {from, to} = window(span, at)

    fleet_id
    |> Atlas.swarm!(span, from, to, %{source: source, by: [:project]}, read_as)
    |> titled(fleet_id)
    |> Enum.sort_by(&{-&1.changes, -&1.actors, &1.project})
  end

  @doc """
  A page of the window's things with the most changes, then the most Keys,
  first. Options: `:source`, `:project`, `:kind`, `:limit` (1 to 200) and
  `:after`, besides `read_as`.
  """
  def most_active(fleet_id, span, at, opts),
    do: page(&Atlas.most_active!/5, fleet_id, span, at, opts)

  @doc "As `most_active/4`, the thing changed last first."
  def newest(fleet_id, span, at, opts),
    do: page(&Atlas.newest_things!/5, fleet_id, span, at, opts)

  defp page(read, fleet_id, span, at, opts) do
    params = opts |> Keyword.take([:source, :project, :kind]) |> Map.new()
    paging = [limit: Keyword.fetch!(opts, :limit)] ++ after_(opts[:after])

    page =
      read.(
        fleet_id,
        span,
        at,
        params,
        [page: paging, load: [:title, :space]] ++ Keyword.take(opts, [:actor, :context])
      )

    %{
      things: Enum.map(page.results, &thing(fleet_id, &1)),
      after: if(page.more?, do: List.last(page.results).__metadata__.keyset)
    }
  end

  defp after_(nil), do: []
  defp after_(cursor), do: [after: cursor]

  defp thing(fleet_id, row) do
    %{
      id: row.thing,
      kind: row.kind,
      what: what(row.kind),
      project: row.project,
      title: row.title || what(row.kind),
      key: row.last_key,
      who: row.last_key && "Key #{grouped(row.last_key)}",
      at: row.last_at,
      changes: row.changes,
      actors: row.actors,
      path: path(fleet_id, row),
      live?: row.kind != Source.notebook_kind()
    }
  end

  @doc "What a thing of `kind` is, in a word or two."
  def what(kind) do
    if kind == Source.notebook_kind() do
      "Notebook"
    else
      {singular, _plural} = WorkspacePage.type_name(kind)
      String.capitalize(singular)
    end
  end

  defp path(fleet_id, %{kind: kind, thing: id, space: space}) do
    if kind == Source.notebook_kind(),
      do:
        "/keyfleet/fleets/#{fleet_id}/notebooks/open?" <>
          URI.encode_query(to: Notebooks.notebook_path(space, id)),
      else: WorkspacePage.item_path(fleet_id, id)
  end
end
