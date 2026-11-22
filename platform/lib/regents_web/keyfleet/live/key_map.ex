defmodule RegentsWeb.Keyfleet.KeyMap do
  @moduledoc """
  What a fleet page's key map is told: every key's two marks when it loads,
  and the marks of the keys that have just changed after that.

  A key's marks are whether one of the viewer's wallets holds it and whether
  it has an active shard today. Someone signed out holds nothing. Owners are never
  sent to the map; the map draws every key sold and the rest of the level on
  sale, so how many are sold travels with the marks.

  A search marks the keys it finds: one key by its number, or every key a
  wallet address holds in the fleet now. Who holds each key is on its page and
  in the Member List for anyone to read, so a search tells nobody anything new.

  A sold key is drawn as its card's close-up. The map asks for the close-ups
  of the keys in view, a hundred at a time, and draws a key by its number
  until its close-up is made.
  """

  import Regents.Keyfleet.Fleets.Rules, only: [grouped: 1, keys: 1]

  alias Regents.Account.Actors.Human
  alias Regents.Keyfleet.Fleets.Presets
  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.Keys.Metadata

  # A change naming more keys than this is sent as a signal to load again,
  # which costs less than the change itself.
  @reset_above 2_000

  @doc """
  The map's first load: keys sold, the fleet's size (`nil` for a fleet whose
  levels keep opening), whether its keys are given rather than sold, and the
  viewer's held keys and the keys with active shards as `bitset/1`s.
  """
  def snapshot(fleet_id, %{total_minted: minted, max_supply: max_supply}, actor) do
    %{
      minted: minted,
      max_supply: max_supply,
      given: Presets.given?(fleet_id),
      mine: bitset(held(fleet_id, actor, [])),
      agent: bitset(Enum.map(Keys.keys_with_shards!(fleet_id), & &1.token_id))
    }
  end

  @doc """
  What the map is told once `token_ids` have changed: `{:patch, patch}` with
  each key's marks as `[token_id, flags]`, bit 0 held by the viewer and bit 1
  an active shard, or `:reset` when more than #{@reset_above} keys changed.
  """
  def change(fleet_id, %{total_minted: minted}, token_ids, actor) do
    token_ids = token_ids |> Enum.uniq() |> Enum.sort()

    if length(token_ids) > @reset_above do
      :reset
    else
      only = [filter: [token_id: [in: token_ids]]]
      mine = MapSet.new(held(fleet_id, actor, only))

      agent = MapSet.new(Keys.keys_with_shards!(fleet_id, query: only), & &1.token_id)

      {:patch,
       %{
         minted: minted,
         keys: for(id <- token_ids, do: [id, flag(mine, id, 1) + flag(agent, id, 2)])
       }}
    end
  end

  # How many keys' close-ups one ask may name.
  @pictures_asked 100

  @doc """
  Where the close-ups of the keys `token_ids` are shown, as
  `[token_id, address]` for each sold key among them whose card has one.
  `deck` is the fleet's `id`, `deck_hash` and `deck_size`. An ask naming more
  than #{@pictures_asked} keys, or anything but a list, is answered with none.
  """
  def pictures(deck, %{total_minted: minted}, token_ids)
      when is_list(token_ids) and length(token_ids) <= @pictures_asked do
    sold = for id <- token_ids, is_integer(id), id in 1..minted//1, uniq: true, do: id
    %{pictures: for({id, address} <- Metadata.close_ups(deck, sold), do: [id, address])}
  end

  def pictures(_deck, _progress, _token_ids), do: %{pictures: []}

  @doc """
  Whether key `token_id` can be chosen on the map: every key minted, and the
  next one on sale.
  """
  def choosable?(%{total_minted: minted, next_token_id: next}, token_id),
    do: is_integer(token_id) and token_id in 1..max(minted, next || 0)//1

  @doc """
  What a search of the map found: the keys to mark, as a `bitset/1`, and a
  few words saying so. A number finds that key once it can be chosen; a wallet
  address finds every key it holds in the fleet now, or says the search
  couldn't be run; nothing typed clears the marks.
  """
  def find(fleet_id, progress, query) when is_binary(query) do
    case sought(String.trim(query)) do
      :nothing ->
        found([], "")

      {:key, token_id} ->
        if choosable?(progress, token_id),
          do: found([token_id], "Key #{grouped(token_id)}."),
          else: found([], "No Key #{grouped(token_id)} yet.")

      {:wallet, wallet} ->
        held_by(fleet_id, wallet)

      :unreadable ->
        found([], "Enter a Key number or a 0x address.")
    end
  end

  def find(_fleet_id, _progress, _query), do: found([], "Enter a Key number or a 0x address.")

  defp held_by(fleet_id, wallet) do
    case RegentsWeb.Keyfleet.PageRead.run("map search", fn ->
           Keys.keys_held_in_fleet!(fleet_id, [wallet])
         end) do
      {:ok, keys} ->
        token_ids = Enum.map(keys, & &1.token_id)

        found(
          token_ids,
          "#{RegentFormat.short_address(wallet)} holds #{keys_held(token_ids)} here."
        )

      {:error, _failure} ->
        found([], "That search couldn’t be run. Try again in a moment.")
    end
  end

  defp sought(""), do: :nothing

  defp sought(query) do
    cond do
      query =~ ~r/\A[0-9]{1,12}\z/ -> {:key, String.to_integer(query)}
      query =~ ~r/\A0x[0-9a-fA-F]{40}\z/ -> {:wallet, String.downcase(query)}
      true -> :unreadable
    end
  end

  defp found(token_ids, words), do: %{keys: bitset(token_ids), words: words}

  defp keys_held([]), do: "no Keys"
  defp keys_held(token_ids), do: keys(length(token_ids))

  @doc """
  The levels the map can go to, which are the levels it draws: each level
  with a key sold and the level of the next key on sale. Fleets without
  levels have none.
  """
  def levels(%{completed_levels: nil}), do: []
  def levels(%{completed_levels: completed}), do: Enum.to_list(1..(completed + 1))

  @doc """
  The keys numbered in `token_ids` as base64, over as many bytes as the
  highest of them needs: key `id` is bit `(id - 1) rem 8`, least significant
  first, of byte `(id - 1) div 8`.
  """
  def bitset(token_ids) do
    set = MapSet.new(token_ids)
    bytes = div(Enum.max(token_ids, fn -> 0 end) + 7, 8)

    # Each byte is written from its most significant bit down.
    bits =
      for byte <- 0..(bytes - 1)//1, bit <- 7..0//-1, into: <<>> do
        <<flag(set, byte * 8 + bit + 1, 1)::1>>
      end

    Base.encode64(bits)
  end

  defp held(fleet_id, %Human{wallet_addresses: [_ | _] = wallets} = actor, query) do
    fleet_id
    |> Keys.keys_held_in_fleet!(wallets, actor: actor, query: query)
    |> Enum.map(& &1.token_id)
  end

  defp held(_fleet_id, _actor, _query), do: []

  defp flag(set, id, value), do: if(MapSet.member?(set, id), do: value, else: 0)
end
