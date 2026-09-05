defmodule AshPlatform.Ens.AvatarHttpClient do
  @moduledoc false
  def head(url, options), do: Req.head(url, options)
end
