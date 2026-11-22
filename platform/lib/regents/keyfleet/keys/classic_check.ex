defmodule Regents.Keyfleet.Keys.ClassicCheck do
  @moduledoc """
  Checks that Classic #1's Keys show what its deployed record promises, and
  raises naming the first thing that does not:

    * the record holds Classic #1 (type `classic`, set 1), whose deck ships in
      `priv/decks` with `keccak256` of its bytes the record's `deckHash`, made
      for `CLASSIC #1`, with the record's `deckSize` cards, drawing from the
      record's trait table, which ships in `priv/trait_tables`;
    * the site's Classic #1 is bound to that record's contracts, deck and
      trait table (`mix keyfleet.seed_deployment`);
    * Key 1's metadata names Set Type `Classic` and Set ID `001`, then every
      trait of the table in its order, and its card is published: kept on
      IPFS, and served as a card picture from the address its `image` names.

  `mix keyfleet.check_classic <deployed record>` runs it, after a Key is
  bought on a fork and the chain reader has recorded it, and again on Base
  once Key 1 has sold.
  """

  alias Regents.Keyfleet.{Decks, Fleets, Traits}
  alias Regents.Keyfleet.Fleets.Fleet
  alias Regents.Keyfleet.Keys.{KeyArt, Metadata}

  @fleet_id "fleet_tech_classic"
  @set [%{trait_type: "Set Type", value: "Classic"}, %{trait_type: "Set ID", value: "001"}]

  @doc """
  Checks the deployed record at `path` (the JSON
  `contracts/script/RecordKeyfleets.s.sol` writes) against the deck and trait
  table the release ships, the site's Classic #1 and Key 1's metadata. Prints
  what it checked and returns `:ok`, or raises.
  """
  # The path is the operator's own argument on the machine they are signed in to.
  # sobelow_skip ["Traversal.FileModule"]
  def run!(path) do
    %{"traitTableHash" => table_hash, "fleets" => fleets} =
      path |> File.read!() |> Jason.decode!()

    table_hash = String.downcase(table_hash)
    record = classic!(fleets)
    deck_hash = String.downcase(record["deckHash"])

    deck = deck!(deck_hash, record["deckSize"], table_hash)
    table = Traits.table!(table_hash)
    fleet = bound!(record, deck_hash, table_hash)
    metadata = key_one!(fleet)

    {set, traits} = Enum.split(metadata.attributes, length(@set))
    check!(set == @set, "Key 1 shows #{inspect(set)}, not Set Type Classic and Set ID 001")

    check!(
      Enum.map(traits, & &1.trait_type) == Enum.map(table, & &1.name),
      "Key 1's traits #{inspect(Enum.map(traits, & &1.trait_type))} are not the table's " <>
        inspect(Enum.map(table, & &1.name))
    )

    published!(metadata)

    IO.puts("""
    Classic #1 matches #{path}:
      deck #{deck_hash}: CLASSIC #1, #{tuple_size(deck.cards)} cards, table #{table_hash}
      bound to manager #{fleet.manager_address}
      Key 1: Set Type Classic, Set ID 001, #{length(traits)} traits, card at #{metadata.image}\
    """)
  end

  defp classic!(fleets) do
    case for({_number, %{"type" => "classic", "typeNumber" => 1} = record} <- fleets, do: record) do
      [record] -> record
      _none -> raise "the record holds no Classic #1 (type classic, set 1)"
    end
  end

  # `Decks.deck!/1` raises for a deck not shipped, or one whose bytes do not
  # hash to its name.
  defp deck!(deck_hash, deck_size, table_hash) do
    deck = Decks.deck!(deck_hash)
    check!(deck.fleet == "CLASSIC #1", "the deck #{deck_hash} was made for #{deck.fleet}")

    check!(
      tuple_size(deck.cards) == deck_size,
      "the deck #{deck_hash} has #{tuple_size(deck.cards)} cards, the record says #{deck_size}"
    )

    check!(
      deck.table == table_hash,
      "the deck #{deck_hash} draws from #{deck.table}, the record's table is #{table_hash}"
    )

    deck
  end

  defp bound!(record, deck_hash, table_hash) do
    fleet = Fleets.get_fleet!(@fleet_id)

    check!(
      fleet.manager_address == String.downcase(record["manager"]) and
        fleet.deck_hash == deck_hash and fleet.deck_size == record["deckSize"] and
        fleet.trait_table_hash == table_hash,
      "the site's Classic #1 is not bound to this record; run mix keyfleet.seed_deployment with it"
    )

    fleet
  end

  defp key_one!(fleet) do
    case fleet |> Fleet.onchain_token_id(1) |> Integer.to_string() |> Metadata.for_key() do
      {:revealed, metadata} ->
        metadata

      {:drawing, _metadata} ->
        raise "Key 1's card is not drawn and kept on IPFS yet; check the key_art queue"

      :not_found ->
        raise "Key 1 of Classic #1 is not recorded; buy it, then let the chain reader catch up"
    end
  end

  defp published!(%{image: image, properties: %{card: "ipfs://" <> cid}}) do
    check!(image == KeyArt.link(cid), "Key 1's image #{image} is not its card ipfs://#{cid}")

    case KeyArt.kept(cid) do
      {:ok, _png} -> :ok
      {:error, reason} -> raise "Key 1's card does not publish at #{image}: #{inspect(reason)}"
    end
  end

  defp check!(true, _failure), do: :ok
  defp check!(false, failure), do: raise(failure)
end
