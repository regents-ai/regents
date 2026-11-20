defmodule RegentsWeb.Stake do
  @moduledoc """
  The Stake pages, shell feature and controller.
  """
  use Boundary,
    deps: [RegentsWeb, RegentsWeb.Chain],
    exports: [StakeLive, Staking, StakingPositionController, TokenLinks]
end
