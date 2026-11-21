defmodule Regents.Keyfleet.Proposals.Call do
  @moduledoc """
  One call a proposal makes the treasury make if it is carried out: the
  contract it calls, the ETH it sends with it, in wei, any uint256, and its
  calldata as `0x` hex.
  """
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :target, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]

    # A whole number, which keeps all 78 digits a uint256 can have.
    attribute :value, :integer, allow_nil?: false, public?: true, constraints: [min: 0]

    attribute :data, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/\A0x(?:[0-9a-f]{2})*\z/, trim?: false]
  end
end
