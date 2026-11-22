defmodule Regents.Keyfleet.Traits do
  @moduledoc """
  Every revealed key's traits, drawn from its seed and the trait table by the
  rule in `contracts/README.md`.

  A fleet's table is the JSON file named by its trait table hash, lowercase,
  in the release's `priv/trait_tables`, such as
  `priv/trait_tables/0xa0a1…64fe.json` (`config :regents, Regents.Keyfleet.Traits,
  directory: ...`). It is an object whose
  `traits` lists each trait in the order the draw takes them, with its `name`
  and its `values`, each a `name` and a whole-number `weight`:

      {"traits": [{"name": "Hull", "values": [{"name": "Brass", "weight": 50}, ...]}, ...]}

  A table is used only when `keccak256` of the file's bytes, exactly as they
  are, is the fleet's trait table hash, and each trait's weights add up to at
  least 1 and less than 2^32. Anything else raises. A table that passed is
  kept for the life of the node.
  """

  @two_to_32 4_294_967_296

  @doc """
  The trait table whose hash is `trait_table_hash`, as a list of traits in
  draw order, each `%{name: name, values: [{value, weight}], total: total}`.
  """
  def table!("0x" <> _ = trait_table_hash) do
    directory = Application.fetch_env!(:regents, __MODULE__)[:directory]
    path = Path.join(directory, trait_table_hash <> ".json")
    key = {__MODULE__, path}

    case :persistent_term.get(key, nil) do
      nil ->
        table = load!(path, trait_table_hash)
        :persistent_term.put(key, table)
        table

      table ->
        table
    end
  end

  @doc """
  The traits drawn for `seed`, a `0x` 32-byte hex string, as `{trait, value}`
  pairs in the table's order. Trait `i`, counting from 0, takes its value from
  word `i`, `keccak256(abi.encode(seed, i))`: with `u` the word's top 32 bits
  and `total` the trait's weights added up, the value is the first whose
  running weight exceeds `floor(u * total / 2^32)`.
  """
  def draw(table, "0x" <> hex) do
    seed = Base.decode16!(hex, case: :lower)

    table
    |> Enum.with_index()
    |> Enum.map(fn {%{name: name, values: values, total: total}, i} ->
      <<u::32, _rest::binary>> = ExKeccak.hash_256(seed <> <<i::256>>)
      {name, pick(values, div(u * total, @two_to_32), 0)}
    end)
  end

  @doc "`keccak256` of `bytes`, as a `0x` hex string."
  def keccak256(bytes), do: "0x" <> Base.encode16(ExKeccak.hash_256(bytes), case: :lower)

  defp pick([{value, weight} | rest], draw, running) do
    if running + weight > draw, do: value, else: pick(rest, draw, running + weight)
  end

  # The file is named by a hash from the fleet's own record, in a directory
  # the app's configuration names.
  # sobelow_skip ["Traversal.FileModule"]
  defp load!(path, trait_table_hash) do
    bytes = File.read!(path)

    if keccak256(bytes) != trait_table_hash do
      raise "the trait table at #{path} does not hash to #{trait_table_hash}"
    end

    %{"traits" => [_ | _] = traits} = Jason.decode!(bytes)
    Enum.map(traits, &trait!/1)
  end

  defp trait!(%{"name" => name, "values" => [_ | _] = values})
       when is_binary(name) and name != "" do
    values = Enum.map(values, &value!/1)
    total = values |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    unless total in 1..(@two_to_32 - 1) do
      raise "the trait table's #{name} weights add up to #{total}, not 1 to 2^32 - 1"
    end

    %{name: name, values: values, total: total}
  end

  defp value!(%{"name" => name, "weight" => weight})
       when is_binary(name) and name != "" and is_integer(weight) and weight >= 0,
       do: {name, weight}
end
