defmodule Regents.Keyfleet.Treasury.AssetBalance do
  @moduledoc """
  One asset the daily split shares, in a `Regents.Keyfleet.Treasury.Reading`: what
  the fleet's treasury holds of it (`held`) and what its reward ledger holds
  for the keys and their former holders (`backed`). Amounts are in the
  asset's atomic units, any uint256; ETH is the zero address. A token's
  symbol and decimals are its `Regents.Keyfleet.Treasury.AssetDetails`.
  """
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :asset, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]

    # Whole numbers, which keep all 78 digits a uint256 can have in the
    # stored reading.
    for field <- [:held, :backed] do
      attribute field, :integer, allow_nil?: false, public?: true, constraints: [min: 0]
    end
  end
end
