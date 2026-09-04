defmodule AshPlatform.Staking.PriceHttpClient do
  @moduledoc false
  def get(url, options), do: Req.get(url, options)
end
