defmodule Regents.Keyfleet.Decks do
  @moduledoc """
  A fleet's card deck: a fixed list of cards made before the fleet is created,
  whose hash the fleet's record on chain keeps for good. A card is a seed; a
  key dealt card `i` shows the traits `Regents.Keyfleet.Traits.draw/2` gives that seed
  from the deck's trait table, under the key's own top line. A founding
  fleet's Key N is dealt card N − 1 (`Regents.Keyfleet.Keys.card_seed/2`).

  Nothing about a card is drawn, stored or served before the key it is dealt
  to is minted: its picture is drawn and kept on IPFS only after that, like
  every key's (`Regents.Keyfleet.Keys.DrawPicture`).

  A deck is the JSON file named by its hash, lowercase, in the release's
  `priv/decks` (`config :regents, Regents.Keyfleet.Decks, directory: ...`). It names the fleet it was
  made for, the hash of the trait table its cards draw from, and the cards,
  each a `0x` 32-byte lowercase hex seed, numbered from 0 in the order listed:

      {"fleet": "CLASSIC #1", "table": "0xa0a1…64fe", "cards": ["0x…", ...]}

  A deck is used only when `keccak256` of the file's bytes, exactly as they
  are, is the hash asked for, its table hash and every card are 32 bytes of
  lowercase hex, and it has at least one card. Anything else raises. A deck
  that passed is kept for the life of the node.
  """

  alias Regents.Keyfleet.Traits

  @doc """
  The deck whose hash is `deck_hash`, as `%{fleet: fleet, table: table_hash,
  cards: cards}` with the cards a tuple, card `i` at index `i`.
  """
  def deck!("0x" <> _ = deck_hash) do
    directory = Application.fetch_env!(:regents, __MODULE__)[:directory]
    path = Path.join(directory, deck_hash <> ".json")
    key = {__MODULE__, path}

    case :persistent_term.get(key, nil) do
      nil ->
        deck = load!(path, deck_hash)
        :persistent_term.put(key, deck)
        deck

      deck ->
        deck
    end
  end

  @doc "The hashes of the decks in the deck directory, in order."
  def hashes do
    Application.fetch_env!(:regents, __MODULE__)[:directory]
    |> Path.join("0x*.json")
    |> Path.wildcard()
    |> Enum.map(&Path.basename(&1, ".json"))
    |> Enum.sort()
  end

  @doc """
  A new deck's file for `fleet`, `size` cards drawing from the trait table
  `table_hash`, each card a seed of 32 random bytes: `{deck_hash, bytes}`.
  With every card a fresh seed, a deck holds each rarity at the table's odds.
  """
  def new(fleet, "0x" <> _ = table_hash, size) when is_binary(fleet) and size > 0 do
    cards =
      for _ <- 1..size,
          do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)

    bytes = encode(fleet, table_hash, cards)
    {Traits.keccak256(bytes), bytes}
  end

  # One card a line, so a deck reads and compares line by line.
  defp encode(fleet, table_hash, cards) do
    lines = Enum.map_join(cards, ",\n", &"    #{Jason.encode!(&1)}")

    """
    {
      "fleet": #{Jason.encode!(fleet)},
      "table": #{Jason.encode!(table_hash)},
      "cards": [
    #{lines}
      ]
    }
    """
  end

  # The file is named by a hash from the fleet's own record, in a directory
  # the app's configuration names.
  # sobelow_skip ["Traversal.FileModule"]
  defp load!(path, deck_hash) do
    bytes = File.read!(path)

    if Traits.keccak256(bytes) != deck_hash do
      raise "the deck at #{path} does not hash to #{deck_hash}"
    end

    %{"fleet" => fleet, "table" => table_hash, "cards" => [_ | _] = cards} = Jason.decode!(bytes)

    unless is_binary(fleet) and fleet != "" and Enum.all?([table_hash | cards], &word?/1) do
      raise "the deck at #{path} needs a fleet, and a table hash and cards of 32 bytes of hex"
    end

    %{fleet: fleet, table: table_hash, cards: List.to_tuple(cards)}
  end

  defp word?(value), do: is_binary(value) and value =~ ~r/\A0x[0-9a-f]{64}\z/
end
