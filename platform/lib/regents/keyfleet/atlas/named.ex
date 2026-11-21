defmodule Regents.Keyfleet.Atlas.Named do
  @moduledoc """
  What each thing of a read of `Regents.Keyfleet.Atlas.Thing` is called now
  (`field: :title`), or which space of the hub a notebook is in
  (`field: :space`): an item's from the workspace's read tables, a notebook's
  from what the hub last listed (`Regents.Keyfleet.Atlas.Notebook`). Each source is
  read once for the whole page. The read they belong to was already allowed as
  the workspace is read, so these are read without asking again.
  """
  use Ash.Resource.Calculation

  alias Regents.Keyfleet.{Atlas, Graph}
  alias Regents.Keyfleet.Atlas.Source

  @impl true
  def load(_query, _opts, _context), do: [:fleet_id, :thing, :kind]

  @impl true
  def calculate([], _opts, _context), do: {:ok, []}

  def calculate([%{fleet_id: fleet_id} | _] = things, opts, _context) do
    {notebooks, items} = Enum.split_with(things, &(&1.kind == Source.notebook_kind()))
    names = names(opts[:field], fleet_id, ids(items), ids(notebooks))
    {:ok, Enum.map(things, &names[&1.thing])}
  end

  defp ids(things), do: things |> Enum.map(& &1.thing) |> Enum.uniq()

  defp names(:title, fleet_id, items, notebooks) do
    # The Atlas read these titles belong to was allowed as the workspace is.
    titles =
      if items == [],
        do: %{},
        else:
          fleet_id
          |> Graph.object_titles!(items, authorize?: false)
          |> Map.new(&{&1.id, &1.title})

    Map.merge(titles, Map.new(notebooks(fleet_id, notebooks), &{&1.id, &1.title}))
  end

  defp names(:space, fleet_id, _items, notebooks),
    do: Map.new(notebooks(fleet_id, notebooks), &{&1.id, &1.space})

  defp notebooks(_fleet_id, []), do: []

  # The Atlas read these notebooks belong to was allowed as the workspace is.
  defp notebooks(fleet_id, ids),
    do: Atlas.notebooks_with_ids!(fleet_id, ids, authorize?: false)
end
