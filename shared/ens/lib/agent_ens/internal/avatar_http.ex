defmodule AgentEns.Internal.AvatarHTTP do
  @moduledoc false

  # Asks the ENS avatar service whether it has a picture for a name.
  @callback head(String.t(), keyword()) :: {:ok, %{status: integer()}} | {:error, term()}

  def head(url, options), do: Req.head(url, options)
end
