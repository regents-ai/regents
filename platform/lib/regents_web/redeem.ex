defmodule RegentsWeb.Redeem do
  @moduledoc """
  The Redeem pages, gallery and shell features.
  """
  use Boundary,
    deps: [RegentsWeb, RegentsWeb.Chain],
    exports: [Gallery, RedeemGalleryLive, Redemption]
end
