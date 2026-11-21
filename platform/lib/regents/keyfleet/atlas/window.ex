defmodule Regents.Keyfleet.Atlas.Window do
  @moduledoc """
  Keeps a read of `Regents.Keyfleet.Atlas.Thing` to one window: the fleet's bucket
  of `span` holding `at`, and of it only the things of `source`, `project`
  and `kind` when they are given.
  """
  use Ash.Resource.Preparation

  require Ash.Query

  import Ash.Expr, only: [ref: 1]

  alias Regents.Keyfleet.Atlas.{Source, Span}

  @impl true
  def prepare(query, _opts, _context) do
    fleet_id = Ash.Query.get_argument(query, :fleet_id)
    span = Ash.Query.get_argument(query, :span)
    start = Span.start(span, DateTime.truncate(Ash.Query.get_argument(query, :at), :second))

    query
    |> Ash.Query.filter(fleet_id == ^fleet_id and span == ^span and start == ^start)
    |> source(Ash.Query.get_argument(query, :source))
    |> narrow(:project, Ash.Query.get_argument(query, :project))
    |> narrow(:kind, Ash.Query.get_argument(query, :kind))
  end

  defp source(query, nil), do: query
  defp source(query, :graph), do: Ash.Query.filter(query, kind != ^Source.notebook_kind())
  defp source(query, :notebook), do: Ash.Query.filter(query, kind == ^Source.notebook_kind())

  defp narrow(query, _field, nil), do: query
  defp narrow(query, field, value), do: Ash.Query.filter(query, ^ref(field) == ^value)
end
