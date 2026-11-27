defmodule RegentsWeb.Keyfleet.FleetPage do
  @moduledoc """
  What a fleet's page reads: the reader's own keys, the key on offer, the key
  the map has chosen, and the hall's feed with what the fleet is recent work.
  """

  alias Regents.Keyfleet.Activity
  alias Regents.Keyfleet.Fleets.Presets
  alias Regents.Keyfleet.Graph
  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.Keys.Metadata
  alias RegentsWeb.Keyfleet.BoxLimit
  alias RegentsWeb.Keyfleet.DirectoryMD
  alias RegentsWeb.Keyfleet.KeyMap

  # How many of a holder's cards the way in shows.
  @cards_shown 50

  @doc """
  The Keys of the fleet the signed-in person holds, for the way in: the
  lowest, how many, and the first fifty by number, each with its small card
  (`nil` until it is made), as
  `%{first: token_id, count: count, cards: cards}`, or `nil` for someone
  holding none. `deck` is the fleet's `id`, `deck_hash` and `deck_size`, which
  say which card each Key shows.
  """
  def held(deck, actor) do
    with %{token_ids: token_ids} = held <- Keys.held_summary(actor, deck.id, @cards_shown) do
      images = Metadata.small_cards(deck, token_ids)

      %{
        first: held.first,
        count: held.count,
        cards: for(token_id <- token_ids, do: %{token_id: token_id, image: images[token_id]})
      }
    end
  end

  @doc """
  The key on offer now, which moves on with every sale; `nil` for the Regents
  Club, whose keys are given, never offered.
  """
  def next_sale(fleet_id, progress) do
    if not Presets.given?(fleet_id),
      do: %{token_id: progress.next_token_id, price: progress.next_price}
  end

  @doc """
  The longest Key or Pass number the page reads, from its address or the
  Pass box (`RegentsWeb.Keyfleet.BoxLimit`).
  """
  def longest_key, do: 20

  @doc """
  A key in the address, or a Pass typed, that isn't one the map shows is no
  choice at all, and nor is one longer than `longest_key/0`.
  """
  def chosen_key(progress, key) when is_binary(key) do
    case Integer.parse(key) do
      {token_id, ""} ->
        if not BoxLimit.too_long?(key, longest_key()) and KeyMap.choosable?(progress, token_id),
          do: token_id

      _not_a_number ->
        nil
    end
  end

  def chosen_key(_progress, _key), do: nil

  @doc """
  "Recent Work", beside the hall's feed and on a visitor's workspace: each of
  the fleet's projects with its open goals, as `Regents.Keyfleet.Graph.shown/1`
  reads them, every title as it can be seen. A title with nothing to see
  reads "A project" or "A goal".
  """
  def read_recent_work(fleet_id) do
    for project <- Graph.shown(fleet_id) do
      %{
        name: project.name,
        title: seen(project.title, "A project"),
        goals: Enum.map(project.goals, &seen(&1, "A goal"))
      }
    end
  end

  defp seen(title, untitled) do
    case title |> DirectoryMD.visible() |> String.trim() do
      "" -> untitled
      title -> title
    end
  end

  @doc """
  The first `wanted` pages of the hall's feed, newest first, read with
  `read_as`, the options `Regents.Keyfleet.Activity.page/3` takes besides `:limit`:
  the items, the cursor for the page after them and how many pages were read.
  """
  def activity_pages(fleet_id, wanted, read_as),
    do: activity_pages(fleet_id, read_as, nil, wanted, [])

  defp activity_pages(fleet_id, read_as, cursor, wanted, read) do
    %{items: items, cursor: next} = Activity.page(fleet_id, cursor, read_as)
    read = [items | read]

    if next != nil and length(read) < wanted,
      do: activity_pages(fleet_id, read_as, next, wanted, read),
      else: {read |> Enum.reverse() |> Enum.concat(), next, length(read)}
  end
end
