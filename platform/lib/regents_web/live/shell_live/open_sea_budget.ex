defmodule RegentsWeb.ShellLive.OpenSeaBudget do
  @moduledoc """
  Every owned-collectible lookup spends the site's one OpenSea key, whose
  allowance every visitor shares, so each visitor may only start a few of them
  a minute, counted by client address across all of their open pages. Redeem's
  collection panel and the gallery's "My passes" draw on the same share. A
  lookup past it is shown as unavailable, which is the same thing a page shows
  when OpenSea itself cannot answer.
  """

  alias Regents.RateLimiter

  @window_seconds 60

  @spec claim(String.t()) :: :ok | :limited
  def claim(client_tag) when is_binary(client_tag) do
    case RateLimiter.admit({:open_sea_lookups, client_tag}, per_minute(), @window_seconds) do
      {:ok, _budget} -> :ok
      {:error, :rate_limited, _budget} -> :limited
    end
  end

  defp per_minute, do: Application.fetch_env!(:regents, :opensea_lookups_per_minute)
end
