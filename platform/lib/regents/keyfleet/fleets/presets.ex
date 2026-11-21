defmodule Regents.Keyfleet.Fleets.Presets do
  @moduledoc """
  The supply and price arithmetic of the five fleet presets, mirrored from
  `contracts/src/KeyfleetPresets.sol`.

  Every step is the contract's own integer step, `ceilDiv(previous * n, 100)`
  applied one level or one mint at a time, so a ladder computed here rounds
  exactly where the contract's does.

  Classic's 1,024 prices, 10 USDC for the first key to 100 USDC for the last,
  are read from `classic_key_prices.txt` beside this module, which
  `scripts/classic_prices.py` writes together with the contract's own table.

  Prices are in atomic USDC, millionths of one USDC, and are exactly what a
  purchase pays: the Fibonacci and Accelerant fleets start at the contract's
  `Q_USDC`, 10 USDC, and follow their preset's ladder from there.

  The two Fibonacci fleets have no last level: new levels keep opening by the
  same rule, so they never sell out. Classic (1,024 keys) and Accelerant
  (2,000 keys) have a supply limit.

  The Regents Club is never sold: its 1,998 Keys are given, one for each
  Regents Club Pass, so it has a supply and no price.
  """

  @q_usdc 10_000_000

  @accelerant_max_keys 2_000

  @club_supply 1_998

  # Classic's price table: one whole number of US cents per key, key 1 first.
  @classic_prices_path Path.expand("classic_key_prices.txt", __DIR__)
  @external_resource @classic_prices_path
  @classic_prices @classic_prices_path
                  |> File.read!()
                  |> String.split("\n", trim: true)
                  |> Enum.map(&(String.to_integer(&1) * 10_000))
                  |> List.to_tuple()
  @classic_supply tuple_size(@classic_prices)

  @presets %{
    "fibonacci_syndicate" => :fibonacci,
    "fibonacci_cascade" => :fibonacci,
    "fleet_tech_classic" => :classic,
    "fleet_tech_accelerant" => :accelerant,
    "regents_club" => :regents_club
  }

  @doc """
  Where a fleet stands after `total_minted` primary keys: how many it can ever
  issue (`nil` for the two Fibonacci fleets, which have no limit), how many
  levels are complete (`nil` for the presets without levels), and the next
  key's id and price in atomic USDC, both `nil` once sold out and always for
  the Regents Club, which sells none.
  """
  def progress(fleet_id, total_minted) when is_integer(total_minted) and total_minted >= 0 do
    preset = Map.fetch!(@presets, fleet_id)
    max_supply = preset_supply(preset)

    sold_out? =
      preset == :regents_club or (max_supply != nil and total_minted >= max_supply)

    %{
      total_minted: total_minted,
      max_supply: max_supply,
      completed_levels: completed_levels(preset, total_minted),
      next_token_id: if(sold_out?, do: nil, else: total_minted + 1),
      next_price: if(sold_out?, do: nil, else: next_price(preset, total_minted))
    }
  end

  @doc """
  What the fleet's contract charged, or will charge, for key `token_id` when
  it is sold, in atomic USDC: the price `progress/2` offered once the key
  before it had sold. `nil` for a Regents Club Key, which is given, and for a
  number past the last Key the fleet can ever have.
  """
  def issue_price(fleet_id, token_id) when is_integer(token_id) and token_id >= 1 do
    preset = preset(fleet_id)
    supply = preset_supply(preset)

    if preset == :regents_club or (supply != nil and token_id > supply),
      do: nil,
      else: next_price(preset, token_id - 1)
  end

  @doc "A fleet's preset: `:fibonacci`, `:classic`, `:accelerant` or `:regents_club`."
  def preset(fleet_id), do: Map.fetch!(@presets, fleet_id)

  @doc "How many Keys a fleet can ever have: `nil` for the two Fibonacci fleets, which have no limit."
  def max_supply(fleet_id), do: fleet_id |> preset() |> preset_supply()

  @doc "Whether a fleet's Keys are given, one per Regents Club Pass, rather than sold."
  def given?(fleet_id), do: preset(fleet_id) == :regents_club

  @doc "Whether a fleet's keys come in levels, as the two Fibonacci fleets' do."
  def levelled?(fleet_id), do: Map.fetch!(@presets, fleet_id) == :fibonacci

  @doc "The Fibonacci level that owns a token id."
  def fibonacci_level_of(token_id) when is_integer(token_id) and token_id >= 1,
    do: level_ends() |> Enum.find_index(&(token_id <= &1)) |> Kernel.+(1)

  @doc "A Fibonacci level's price: 10 USDC at level 1, then ×1.2 per level, rounded up at each step."
  def fibonacci_level_price(level) when is_integer(level) and level >= 1,
    do: step(@q_usdc, level - 1, 120)

  @doc "An Accelerant primary mint's price: 10 USDC for the first, then ×1.05 per mint, rounded up."
  def accelerant_price(mint_index) when mint_index in 0..(@accelerant_max_keys - 1)//1,
    do: step(@q_usdc, mint_index, 105)

  defp next_price(:fibonacci, minted), do: fibonacci_level_price(fibonacci_level_of(minted + 1))
  defp next_price(:classic, minted), do: elem(@classic_prices, minted)
  defp next_price(:accelerant, minted), do: accelerant_price(minted)

  defp preset_supply(:fibonacci), do: nil
  defp preset_supply(:classic), do: @classic_supply
  defp preset_supply(:accelerant), do: @accelerant_max_keys
  defp preset_supply(:regents_club), do: @club_supply

  # Token ids are contiguous, so every level before the next key's is complete.
  defp completed_levels(:fibonacci, minted), do: fibonacci_level_of(minted + 1) - 1
  defp completed_levels(_preset, _minted), do: nil

  # Level supplies 2, 3, 5, 8, … without end, and the last token id of each.
  defp level_supplies,
    do:
      Stream.unfold({1, 2}, fn {previous, current} -> {current, {current, previous + current}} end)

  defp level_ends, do: Stream.scan(level_supplies(), &+/2)

  defp step(price, 0, _numerator), do: price

  defp step(price, steps, numerator),
    do: step(ceil_div(price * numerator, 100), steps - 1, numerator)

  defp ceil_div(a, b), do: div(a + b - 1, b)
end
