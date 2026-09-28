defmodule Regents.OpenSea do
  @moduledoc "Server-side OpenSea owned-collectible lookup."
  use Ash.Domain

  resources do
    resource Regents.OpenSea.Holdings do
      define :fetch_owned_collectibles, action: :fetch_owned_collectibles, args: [:address]
    end
  end
end
