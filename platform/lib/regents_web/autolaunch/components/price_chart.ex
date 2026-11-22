defmodule RegentsWeb.Autolaunch.Components.PriceChart do
  @moduledoc """
  How far a token's price has moved since its pool opened, from the line of
  `[block, price]` points its pool read gives (`Regents.Autolaunch.PriceHistory`):
  in words for the page's Change, and as a direction and percent for the move
  beside its price.

  Still to come, with its own part: the chart itself.
  """

  @doc "How far a line of `[block, price]` points moved from its first price to its last, in words."
  @spec change([[number()]]) :: String.t()
  def change(points) do
    case move(points) do
      {:up, percent} -> "Up #{percent}%"
      {:down, percent} -> "Down #{percent}%"
      :unchanged -> "Unchanged"
    end
  end

  @doc """
  Which way a line of `[block, price]` points moved from its first price to its
  last, and by how many percent to one decimal place, or `:unchanged`.
  """
  @spec move([[number()]]) :: {:up | :down, float()} | :unchanged
  def move([[_block, first] | _rest] = points) do
    [_block, last] = List.last(points)
    percent = Float.round((last / first - 1) * 100, 1)

    cond do
      percent > 0 -> {:up, percent}
      percent < 0 -> {:down, abs(percent)}
      true -> :unchanged
    end
  end
end
