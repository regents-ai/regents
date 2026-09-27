defmodule AshPlatformWeb.ShellLive.OpenSeaBudget do
  @moduledoc """
  Every owned-collectible lookup spends the server's own OpenSea credentials on
  behalf of a visitor who needs no account, so one connection may only start a
  few of them a minute. Redeem's collection panel and the gallery's "My passes"
  draw on the same share. A page past its share is told the lookup is
  unavailable, which is the same thing it is told when OpenSea itself cannot
  answer.
  """

  import Phoenix.Component, only: [assign: 3]

  @window 60_000
  @default_per_minute 6

  def init(socket), do: assign(socket, :open_sea_lookup_starts, [])

  @doc "`{:ok, socket}` with the lookup counted, or `{:limited, socket}`."
  def claim(socket) do
    now = System.monotonic_time(:millisecond)
    recent = Enum.filter(socket.assigns.open_sea_lookup_starts, &(&1 > now - @window))

    if length(recent) >= per_minute(),
      do: {:limited, assign(socket, :open_sea_lookup_starts, recent)},
      else: {:ok, assign(socket, :open_sea_lookup_starts, [now | recent])}
  end

  defp per_minute,
    do: Application.get_env(:ash_platform, :opensea_lookups_per_minute, @default_per_minute)
end
