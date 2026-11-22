defmodule RegentsWeb.Keyfleet.SharedFigures do
  @moduledoc """
  The readings every open page shares (`Regents.SharedReading`), as a page
  follows them. A page names the keys each part of it shows, by group; it
  starts hearing a key before it reads it, so a change that lands while it
  reads still reaches it, and stops hearing the keys a part no longer shows.
  """

  import Phoenix.Component, only: [update: 3]
  import Phoenix.LiveView, only: [connected?: 1]

  alias Regents.SharedReading

  @doc """
  Hears `keys` for `group`, and no longer the keys `group` heard before. A key
  another group also follows is heard once, and stays heard while any group
  follows it.
  """
  def follow(socket, group, keys) do
    keys = MapSet.new(keys)
    {held, others} = Map.pop(socket.assigns.shared, group, MapSet.new())
    others = Enum.reduce(Map.values(others), MapSet.new(), &MapSet.union/2)

    if connected?(socket) do
      held
      |> MapSet.difference(keys)
      |> MapSet.difference(others)
      |> Enum.each(&SharedReading.unsubscribe/1)

      keys
      |> MapSet.difference(held)
      |> MapSet.difference(others)
      |> Enum.each(&SharedReading.subscribe/1)
    end

    update(socket, :shared, &Map.put(&1, group, keys))
  end

  @doc "The reading held for `key`, or nil while there is none."
  def reading(key) do
    case SharedReading.fetch(key) do
      {:ok, %{reading: reading}} -> reading
      :error -> nil
    end
  end
end
