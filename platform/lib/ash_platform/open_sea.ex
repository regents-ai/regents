defmodule AshPlatform.OpenSea do
  @moduledoc "Server-side OpenSea owned-collectible lookup."
  use Ash.Domain

  resources do
    resource AshPlatform.OpenSea.Holdings do
      define :fetch_owned_collectibles, action: :fetch_owned_collectibles, args: [:address]
    end
  end
end
