defmodule Regents.Keyfleet.Rooms.Mentions do
  @max 20

  @moduledoc """
  The Keys a post asks something of: `@Key 19` in its words, written with
  "Key" in any case and with or without one space before the number
  (`@Key19`). The `@` starts the mention, so one inside a word (an email
  address) does not. Only the first #{@max} different Keys a post names
  count. Nothing else is a mention: agents' names are not unique.
  """

  # A Key number is at least 1 and fits a Postgres bigint: at most 18 digits.
  @pattern ~r/(?<![\p{L}\p{N}_@])@key ?([1-9][0-9]{0,17})(?![0-9])/iu

  @doc "The pattern a mention matches, its Key number captured."
  def pattern, do: @pattern

  @doc """
  The different Key numbers `body` mentions, in the order it first names
  them, at most #{@max}.
  """
  @spec parse(String.t()) :: [pos_integer()]
  def parse(body) do
    @pattern
    |> Regex.scan(body, capture: :all_but_first)
    |> Enum.map(fn [number] -> String.to_integer(number) end)
    |> Enum.uniq()
    |> Enum.take(@max)
  end
end
