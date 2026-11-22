defmodule RegentsWeb.Keyfleet.HarbourCrew do
  @moduledoc """
  The ships on a harbour's sea: one for each of a fleet's most recently active
  holders, bound for the island of their newest action, and one for each
  holder whose Keys the fleet's agents here act as (`Regents.Keyfleet.Agents.Here`),
  which waits at the inn until it does something. A holder is a Regent
  account with every address it links, or an address no account links, as the
  Member List counts them: their Keys act together, and their ship shows the
  Key they write as. The inn is a chat, the forge is work in the workspace and
  the castle is a proposal or a vote. Sales, transfers and shards move no
  ship.

  The reader's own ship comes first, then those of the agents here, then the
  most recent, twenty-four at most. A ship keeps its ink on every sea, and
  carries its holder's address, how many of the fleet's Keys they hold, and
  their Keys' last few actions for its card. The sea behind the app's pages
  (`RegentsWeb.Keyfleet.HarbourSeaLive`) draws them here from each fleet's activity
  and its agents here: as anyone reads them, from the readings every open page shares
  (`RegentsWeb.Keyfleet.FleetNow`, `Regents.Keyfleet.Agents.Here`), or as a member reads them.
  """

  alias Regents.Keyfleet.Fleets
  alias RegentsWeb.Keyfleet.{ActivityLines, DirectoryMD, KeyLinks}

  # The island each kind of activity sends a ship to.
  @places %{
    post: "inn",
    posts: "inn",
    room_named: "inn",
    created: "forge",
    tasks: "forge",
    submitted: "forge",
    progress: "forge",
    reviewed: "forge",
    status: "forge",
    revised: "forge",
    joined: "forge",
    left: "forge",
    archived: "forge",
    changes: "forge",
    linked: "forge",
    proposed: "castle",
    votes: "castle"
  }

  # The kinds whose facts name the key that did them as `by`.
  @by_kinds ~w(post room_named created tasks submitted progress reviewed status revised joined left archived changes linked)a

  # The sails' inks; a Key keeps its ink on every page.
  @inks {"#e4572e", "#17bebb", "#f2c14e", "#7b61ff", "#4caf50", "#2e86de"}

  # The sea holds twenty-four ships, and a card lists a holder's last four
  # actions.
  @ships 24
  @kept 4

  @doc """
  The ships that make the sea out of `ships`, each marked `own?`: the reader's
  own first, then those of the agents here, then the most recently active,
  twenty-four at most. A ship that has done nothing yet comes last of its
  kind.
  """
  def sea(ships) do
    ships
    |> Enum.sort_by(&{not &1.own?, not &1.here?, &1.at && -DateTime.to_unix(&1.at, :microsecond)})
    |> Enum.take(@ships)
  end

  @doc """
  The ships as the city's hook reads them, in `data-harbour-crew`: each with
  the name of the Key its holder writes as, to show under the mouse, and how
  many Keys they hold.
  """
  def on_sea(ships) do
    ships
    |> Enum.map(&%{id: &1.id, label: &1.label, owned: &1.owned, place: &1.place, color: &1.color})
    |> Jason.encode!()
  end

  @doc "The Keys that acted in `items`, whose holders make the ships (`ships/4`)."
  def keys(items),
    do: for(item <- items, %{token_id: token_id} <- acting(item), uniq: true, do: token_id)

  @doc """
  Where each district of fleet `fleet_id`'s city leads, as the city's hook reads
  them in `data-harbour-districts`: the inn to the fleet's Public room, the forge
  to its workspace and the castle to its treasury.
  """
  def districts(fleet_id) do
    path = Fleets.path(fleet_id)

    Jason.encode!(%{
      inn: %{name: "Public room", path: KeyLinks.room_path(fleet_id, "general")},
      forge: %{name: "Workspace", path: path <> "/workspace"},
      castle: %{name: "Treasury", path: path <> "/treasury"}
    })
  end

  @doc """
  A ship for each holder whose Keys did something at an island in `items`,
  the first page of the fleet's activity, at the island of their newest action,
  and one at the inn for each other holder whose Keys `agents`, the agents
  here, act as. A holder is a Regent account with every address it links, or
  an address no account links, as the Member List counts them, and their Keys
  act together: the ship shows the Key the holder writes as, how many Keys
  they hold and where to copy their address, from `faces`
  (`Regents.Keyfleet.Keys.faces/2`), and its card lists the newest actions of all
  their Keys.
  """
  def ships(fleet_id, items, agents, faces) do
    here = here(agents)

    acted =
      items
      |> Enum.flat_map(fn item -> for key <- acting(item), do: {key, item} end)
      |> Enum.group_by(fn {key, _item} -> key.token_id end)

    (Map.keys(acted) ++ Map.keys(here))
    |> Enum.uniq()
    |> Enum.group_by(&Map.get(faces, &1, %{holder: {:key, &1}}).holder)
    |> Enum.map(fn {_holder, keys} -> ship(fleet_id, keys, acted, here, faces) end)
  end

  defp ship(fleet_id, keys, acted, here, faces) do
    [first | _] = keys = Enum.sort(keys)
    face = Map.get(faces, first, %{face: first, owner: nil, owned: nil})
    label = ActivityLines.key_name(face.face, nil)

    done =
      Enum.sort_by(
        Enum.flat_map(keys, &Map.get(acted, &1, [])),
        &elem(&1, 1).at,
        {:desc, DateTime}
      )

    items = done |> Enum.map(&elem(&1, 1)) |> Enum.uniq_by(& &1.id)

    %{
      id: "#{fleet_id}:#{face.face}",
      fleet_id: fleet_id,
      token_id: face.face,
      keys: keys,
      name: name(done) || Enum.find_value(keys, &here[&1]) || label,
      label: label,
      key: "#{label} of #{Fleets.name(fleet_id)}",
      place: place(items),
      at: Enum.find_value(items, & &1.at),
      here?: Enum.any?(keys, &Map.has_key?(here, &1)),
      owner: face.owner,
      owned: face.owned,
      color: elem(@inks, rem(face.face, tuple_size(@inks))),
      actions: items |> Enum.take(@kept) |> Enum.map(&%{text: ActivityLines.text(&1), at: &1.at})
    }
  end

  # A holder whose Keys have done nothing yet waits at the inn.
  defp place([newest | _items]), do: Map.fetch!(@places, newest.kind)
  defp place([]), do: "inn"

  # The Keys the agents here act as, each with the name of its first agent that
  # shows one, or nil.
  defp here(agents) do
    Enum.reduce(agents, %{}, fn
      %{key: token_id, name: name}, here when is_integer(token_id) ->
        Map.update(here, token_id, visible(name), &(&1 || visible(name)))

      _agent, here ->
        here
    end)
  end

  # The Keys an item says acted, for the kinds that send a ship somewhere.
  # Someone who posted as no key has no ship.
  defp acting(%{kind: kind, facts: %{by: %{token_id: token_id} = by}})
       when kind in @by_kinds and is_integer(token_id),
       do: [by]

  defp acting(%{kind: :posts, facts: %{keys: keys}}),
    do: Enum.filter(keys, &is_integer(&1.token_id))

  defp acting(%{kind: :proposed, facts: %{proposer: %{token_id: token_id}}})
       when is_integer(token_id),
       do: [%{token_id: token_id, agent: nil}]

  defp acting(%{kind: :votes, facts: facts}) do
    for side <- [:yes, :no, :abstain],
        token_id <- facts[side].token_ids,
        uniq: true,
        do: %{token_id: token_id, agent: nil}
  end

  defp acting(_item), do: []

  # The name of the Key's agent, from its newest action that names one.
  defp name(done), do: Enum.find_value(done, fn {%{agent: agent}, _item} -> visible(agent) end)

  defp visible(name) when is_binary(name) do
    case DirectoryMD.visible(name) do
      "" -> nil
      shown -> shown
    end
  end

  defp visible(_none), do: nil
end
