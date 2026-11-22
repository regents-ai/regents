defmodule Regents.Keyfleet.Atlas do
  @moduledoc """
  The fleet's work over time, from the whole swarm down to one thing: every
  change to an item of the workspace and every notebook made or saved,
  counted as it happens into buckets of time, and read at three levels.

  ## What is counted

  A change is one touch of one thing at one time, as one Key or as nobody's
  (`Regents.Keyfleet.Atlas.Count`): an item made or patched in the graph, counted as
  its page is copied (`Regents.Keyfleet.Graph.Projection`, with `Regents.Keyfleet.Atlas.Fill`
  counting what came before), and a notebook made or saved, counted as the
  fleet's hub is read each hour (`Regents.Keyfleet.Atlas.ReadHub`). A thing's
  `kind` is its item type (goal, task, finding and the rest) or `"notebook"`
  (`Regents.Keyfleet.Atlas.Source`); its project is the one it is in.

  Buckets are calendar periods in UTC (`Regents.Keyfleet.Atlas.Span`): an hour, a day,
  a week from Monday, a month and a year. Every change is added to its bucket
  of every span, so a read of a span is a read of that span's own rows and
  never sums finer ones: the things changed in a day and the Keys at work in
  a week are counted exactly, which no sum of hours could give.

  ## The three levels

    1. `swarm/5`: for each bucket of a span in a stretch of time, the changes,
       the things changed and the Keys at work, per project and kind, or
       summed over either (`by:`). At most 1,000 buckets a read. Each answer
       is `%{at, project, kind, changes, things, actors}`.

    2. `most_active/4`: the things of one window (the bucket of a span that
       holds `at`) with the most changes first, then the most Keys, a page at
       a time (keyset, `after:`).

    3. `newest_things/4`: the things of one window, the one changed last
       first, a page at a time.

  Both of the last two answer `Regents.Keyfleet.Atlas.Thing`s, each with `thing`
  (the item's or notebook's id), `kind`, `project`, `changes` and `actors` in
  the window, `last_at` and `last_key` (its last change and as which Key),
  and, loaded on request, `title` and `space` (the notebook's space in the
  hub, which its link opens in). Each narrows to `source:` (graph or
  notebook), `project:` and `kind:`.

  All three are read as the fleet's workspace is: by its members only
  (`Regents.Keyfleet.Access.Check`). Everything else here is the system's.
  """
  use Ash.Domain

  alias Regents.Keyfleet.Atlas

  resources do
    resource Regents.Keyfleet.Atlas.Bucket do
      define :count_buckets, action: :count
    end

    resource Regents.Keyfleet.Atlas.Thing do
      define :swarm, action: :swarm, args: [:fleet_id, :span, :from, :to]
      define :most_active, action: :most_active, args: [:fleet_id, :span, :at]
      define :newest_things, action: :newest, args: [:fleet_id, :span, :at]
      define :existing_things, action: :existing, args: [:fleet_id, :things, :starts]
      define :count_things, action: :count
    end

    resource Regents.Keyfleet.Atlas.Notebook do
      define :notebooks_with_ids, action: :with_ids, args: [:fleet_id, :ids]

      define :last_updated_notebook,
        action: :last_updated,
        args: [:fleet_id, :project],
        get?: true,
        not_found_error?: false

      define :keep_notebooks, action: :keep
    end
  end

  @doc "Where a fleet's Atlas says it has counted more, which only its members hear."
  def topic(fleet_id), do: "keyfleet:fleet:#{fleet_id}:atlas"

  @doc "Says on `topic/1` that the fleet's Atlas has counted more."
  def changed(fleet_id),
    do: Phoenix.PubSub.broadcast(Regents.PubSub, topic(fleet_id), {:atlas_changed, fleet_id})

  @doc """
  Takes the fleet's counted graph work away, as its log starts over
  (`Regents.Keyfleet.Graph.Projection`) with a new cursor that has counted nothing.
  """
  def forget_graph(fleet_id) do
    for resource <- [Atlas.Thing, Atlas.Bucket] do
      resource
      |> Ash.Query.for_read(:of_graph, %{fleet_id: fleet_id},
        actor: %Regents.Account.Actors.System{}
      )
      |> Ash.bulk_destroy!(:forget, %{},
        actor: %Regents.Account.Actors.System{},
        strategy: [:atomic],
        return_errors?: true
      )
    end

    :ok
  end
end
