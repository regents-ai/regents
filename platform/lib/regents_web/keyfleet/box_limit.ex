defmodule RegentsWeb.Keyfleet.BoxLimit do
  @moduledoc """
  How long a text box is, against the longest value the site takes from it.

  A browser counts a box's `maxlength` in UTF-16 units, one for most
  letters and two for an emoji or any other letter past U+FFFF, and cuts a
  paste there without a word, never keeping half of a two-unit letter, so
  what it keeps of a paste longer than the box may be one unit short of it.
  An emoji joined from several letters may be cut between them. A box
  therefore takes two units more than the longest value the site takes from
  it (`maxlength/1`), room for one more letter of any kind.

  The site refuses a value longer than that longest, counted the same way
  and as it was typed, before anything is trimmed (`too_long?/2`), with a
  note saying so: whatever a box cut is longer than that, so it is refused
  and said, never taken as if it had been typed. Where a field's own rule
  counts otherwise once it has trimmed a value, in letters or in bytes (a
  proposal's words and a launch's fields, a poll's choices, the showcase's
  titles), the longest is the most that rule takes written in UTF-16 units,
  so the longest value it takes fits its box; the rule still runs
  afterwards, and may refuse more with its own note. A value at exactly the
  longest is therefore refused as too long once a space or a blank line is
  typed anywhere around or between what it holds, such as a blank line
  between two of a poll's choices, though the rule would leave it out.

  `kept/2` is what a box keeps of a value, for a value the site draws into
  one itself.
  """

  @doc "The `maxlength` of the box whose longest value is `longest` UTF-16 units."
  def maxlength(longest), do: longest + 2

  @doc "Whether `typed` is longer than the `longest` UTF-16 units the site takes."
  # A letter is never fewer bytes than units.
  def too_long?(typed, longest), do: byte_size(typed) > longest and units(typed, 0) > longest

  @doc """
  What the box for `longest` keeps of `value`, as a browser cuts a paste: as
  many whole letters as fit in its `maxlength`.
  """
  def kept(value, longest) do
    room = maxlength(longest)
    if byte_size(value) <= room, do: value, else: binary_part(value, 0, fit(value, room, 0))
  end

  defp units(<<letter::utf8, rest::binary>>, count) when letter > 0xFFFF,
    do: units(rest, count + 2)

  defp units(<<_letter::utf8, rest::binary>>, count), do: units(rest, count + 1)
  defp units(<<_not_a_letter, rest::binary>>, count), do: units(rest, count + 1)
  defp units(<<>>, count), do: count

  # How many bytes of `value` the letters that fit in `room` units take.
  defp fit(<<letter::utf8, rest::binary>> = value, room, bytes) do
    width = if letter > 0xFFFF, do: 2, else: 1
    size = byte_size(value) - byte_size(rest)
    if width <= room, do: fit(rest, room - width, bytes + size), else: bytes
  end

  defp fit(<<_not_a_letter, rest::binary>>, room, bytes) when room >= 1,
    do: fit(rest, room - 1, bytes + 1)

  defp fit(_full_or_done, _room, bytes), do: bytes
end
