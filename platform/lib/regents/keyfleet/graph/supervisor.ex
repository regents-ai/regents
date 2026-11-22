defmodule Regents.Keyfleet.Graph.Supervisor do
  @moduledoc """
  Runs one graph writer per catalog fleet.

  A writer replaces its own failed host with backoff and never exits because a
  host failed, so one fleet's failing host leaves the other fleets alone. The
  writers share a `one_for_one` supervisor.

  Every level restarts what it runs, so a burst of writer crashes can never
  leave the graph stopped while the site keeps serving. The writers'
  supervisor allows three restarts per fleet in five seconds, which lets one
  fleet's writer crash a few times without touching the others; past that
  this supervisor restarts all the writers, past its own limit the
  application restarts the whole graph, and a crash loop that outlasts even
  that stops the application, so the machine restarts with it. While a level
  restarts, graph requests answer `{:error, :unavailable}`.

  Options default to the `:graph` application environment: `:data_dir` holds
  one SQLite file per fleet, `:python` is the graph host's interpreter,
  `:hello_timeout` and `:reply_timeout` are how long a writer waits for a new
  host to answer and for a reply, `:check_timeout` is how long a write's
  ownership check may spend reading, and `:restart_min` and `:restart_max` bound
  the delay before a failed host is replaced. `:fleets` defaults to the fixed
  catalog, and `:starting_goals`, the goals every workspace starts with, to
  `Regents.Keyfleet.GoalIdeas.starting_goals/0`.
  """
  use Supervisor

  alias Regents.Keyfleet.Graph.Writer

  @writer_opts [
    :data_dir,
    :python,
    :hello_timeout,
    :reply_timeout,
    :check_timeout,
    :restart_min,
    :restart_max,
    :starting_goals
  ]

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    opts =
      :regents
      |> Application.fetch_env!(:keyfleet_graph)
      |> Keyword.merge(opts)
      |> Keyword.put_new_lazy(:starting_goals, &Regents.Keyfleet.GoalIdeas.starting_goals/0)

    writer_opts = Keyword.take(opts, @writer_opts)

    writers =
      opts
      |> Keyword.get_lazy(:fleets, &Regents.Keyfleet.Fleets.catalog_ids/0)
      |> Enum.map(&{Writer, [{:fleet_id, &1} | writer_opts]})

    Supervisor.init(
      [
        %{
          id: :writers,
          type: :supervisor,
          start: {Supervisor, :start_link, [writers, writers_options(writers)]}
        }
      ],
      strategy: :one_for_one
    )
  end

  # Three restarts per fleet in five seconds; see the moduledoc.
  defp writers_options(writers),
    do: [strategy: :one_for_one, max_restarts: 3 * length(writers), max_seconds: 5]
end
