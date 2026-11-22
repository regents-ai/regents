defmodule RegentsWeb.Patchbay.ReadLimit do
  @moduledoc """
  Patchbay's rate-limit adapter delegating to the site's shared
  `Regents.RateLimiter`.
  """

  alias Regents.RateLimiter

  @spec admit(term(), pos_integer(), pos_integer()) ::
          {:ok, RegentAgentAccess.RateLimit.budget()}
          | {:error, :rate_limited, RegentAgentAccess.RateLimit.budget()}
  def admit(key, limit, window_seconds),
    do: RateLimiter.admit({:patchbay, key}, limit, window_seconds)
end
