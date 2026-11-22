defmodule Regents.Keyfleet.Graph.Projectors do
  @moduledoc """
  Runs one `Regents.Keyfleet.Graph.Projector` per catalog fleet.

  It runs beside `Regents.Keyfleet.Graph.Supervisor`, not under it: a projector reads
  the log through its fleet's writer, but the writers never depend on the
  projectors, and while a writer is down its projector's rounds fail and are
  retried. The projectors share a `one_for_one` supervisor that allows three
  restarts per fleet in five seconds.

  Options default to the `:graph` application environment:
  `:catch_up_interval` is how often a projector copies the log whether or not
  a write asked it to. `:fleets` defaults to the fixed catalog.
  """
  use Supervisor

  alias Regents.Keyfleet.Graph.Projector

  @projector_opts [:catch_up_interval]

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    opts = Keyword.merge(Application.fetch_env!(:regents, :keyfleet_graph), opts)
    projector_opts = Keyword.take(opts, @projector_opts)

    projectors =
      opts
      |> Keyword.get_lazy(:fleets, &Regents.Keyfleet.Fleets.catalog_ids/0)
      |> Enum.map(&{Projector, [{:fleet_id, &1} | projector_opts]})

    Supervisor.init(
      [
        %{
          id: :projectors,
          type: :supervisor,
          start:
            {Supervisor, :start_link,
             [
               projectors,
               [strategy: :one_for_one, max_restarts: 3 * length(projectors), max_seconds: 5]
             ]}
        }
      ],
      strategy: :one_for_one
    )
  end
end
