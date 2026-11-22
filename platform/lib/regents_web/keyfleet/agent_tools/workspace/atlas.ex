defmodule RegentsWeb.Keyfleet.AgentTools.Workspace.Atlas do
  @moduledoc """
  A fleet's Atlas as an agent reads it, for `RegentsWeb.Keyfleet.AgentTools.Workspace`:
  the swarm's work in one window, by bucket, with its most active things
  (`swarm/2`), and a page of the things changed in one window (`things/2`).
  Each reads through `RegentsWeb.Keyfleet.AtlasPage` as the calling agent, whose
  policies let only the fleet's members read, and answers and refuses as the
  workspace's reads do (`RegentsWeb.Keyfleet.AgentTools.Workspace.Read`).
  """

  alias Ash.Error.Changes.InvalidArgument
  alias Regents.Keyfleet.Atlas.Span
  alias RegentsWeb.Endpoint
  alias RegentsWeb.Keyfleet.AgentTools.Workspace.Read
  alias RegentsWeb.Keyfleet.AtlasPage

  @doc """
  The window holding `at` (now when left out): its totals, its buckets of
  `bucket` that saw work, oldest first, summed by `by` when given, and its
  `most_active` things.
  """
  def swarm(%{fleet_id: fleet_id, window: window} = args, read_as) do
    bucket = args[:bucket] || AtlasPage.bucket(window)

    if bucket in Enum.take_while(Span.all(), &(&1 != window)) do
      fleet_id
      |> read(fn -> swarm(args, bucket, read_as) end)
      |> Read.answer(fleet_id)
    else
      {:error,
       InvalidArgument.exception(field: :bucket, message: "must be shorter than the window")}
    end
  end

  defp swarm(%{fleet_id: fleet_id, window: window} = args, bucket, read_as) do
    at = args[:at] || DateTime.utc_now()
    {start, finish} = AtlasPage.window(window, at)
    by = List.wrap(args[:by])
    filter = %{source: args[:source], project: args[:project]}

    totals =
      case AtlasPage.swarm(fleet_id, window, start, finish, Map.put(filter, :by, []), read_as) do
        [cell] -> Map.take(cell, [:changes, :things, :actors])
        [] -> %{changes: 0, things: 0, actors: 0}
      end

    buckets =
      fleet_id
      |> AtlasPage.swarm(bucket, start, finish, Map.put(filter, :by, by), read_as)
      |> Enum.map(&Map.take(&1, [:at, :changes, :things, :actors | by]))

    %{
      window: %{span: window, start: start, end: finish},
      bucket: bucket,
      totals: totals,
      buckets: buckets,
      most_active: most_active(args, at, read_as)
    }
  end

  defp most_active(%{most_active: 0}, _at, _read_as), do: []

  defp most_active(%{fleet_id: fleet_id, window: window, most_active: limit} = args, at, read_as) do
    opts = [limit: limit, source: args[:source], project: args[:project]] ++ read_as
    Enum.map(AtlasPage.most_active(fleet_id, window, at, opts).things, &thing/1)
  end

  @doc """
  A page of the things changed in the window holding `at` (now when left
  out), the one changed last first, or the most active first, from `after`.
  """
  def things(%{fleet_id: fleet_id, window: window} = args, read_as) do
    at = args[:at] || DateTime.utc_now()
    {start, finish} = AtlasPage.window(window, at)

    opts =
      [
        limit: args.limit,
        after: args[:after],
        source: args[:source],
        project: args[:project],
        kind: args[:kind]
      ] ++ read_as

    fleet_id
    |> read(fn ->
      page = page(args.order, fleet_id, window, at, opts)

      %{
        window: %{span: window, start: start, end: finish},
        things: Enum.map(page.things, &thing/1),
        next_after: page.after
      }
    end)
    |> Read.answer(fleet_id)
  end

  defp page(:newest, fleet_id, window, at, opts), do: AtlasPage.newest(fleet_id, window, at, opts)

  defp page(:active, fleet_id, window, at, opts),
    do: AtlasPage.most_active(fleet_id, window, at, opts)

  # A fleet the workspace doesn't know is refused as its reads refuse it, and
  # what the Atlas's own reads raise (a reader who isn't a member, a stretch
  # of too many buckets, a page cursor that isn't one) is answered as theirs.
  defp read(fleet_id, read) do
    with :ok <- Read.known_fleet(fleet_id), do: {:ok, read.()}
  rescue
    error in [Ash.Error.Forbidden, Ash.Error.Invalid, Ash.Error.Unknown] -> {:error, error}
  end

  defp thing(thing) do
    %{
      id: thing.id,
      kind: thing.kind,
      project: thing.project,
      title: thing.title,
      key: thing.key,
      changed_at: thing.at,
      changes: thing.changes,
      actors: thing.actors,
      page: Endpoint.url() <> thing.path
    }
  end
end
