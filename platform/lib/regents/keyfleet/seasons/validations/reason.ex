defmodule Regents.Keyfleet.Seasons.Validations.Reason do
  @moduledoc """
  A pick's reason is one line of ordinary text a person types
  (`Regents.Keyfleet.Seasons.SeasonPick`), checked once Ash has trimmed it. The first
  rule it breaks refuses it (`Regents.Keyfleet.Seasons.Errors.ReasonError`, whose
  `rule` is the one named here):

    * `:plain`: valid UTF-8 with no control character, no line or paragraph
      separator, and no format character or character drawn as nothing (every
      default-ignorable one, the blank Braille pattern and the null notehead)
      but these:
        - anywhere, as ordinary writing types them: the soft hyphen, the
          zero-width space, non-joiner and joiner, the left-to-right,
          right-to-left and Arabic letter marks, the Mongolian vowel separator
          and the word joiner;
        - a variation selector directly after a character it can vary (an
          emoji's after an emoji, an ideograph's after an ideograph, a
          Mongolian one after a Mongolian letter, any other after a letter,
          digit, punctuation mark or symbol) or after a character Unicode has
          not yet assigned, a noncharacter aside;
        - the tags of the flags of England, Scotland and Wales.
      So the characters that turn text around or wall it off, the tags that
      could carry text a person can't see, and the Hangul fillers are refused;
    * `:too_long`: at most `longest/0` UTF-16 units, as a text box counts what
      is typed (`RegentsWeb.Keyfleet.BoxLimit`): one for most letters, two for an
      emoji, and an emoji joined from several counts them all;
    * `:blank`: at least one character that shows: a letter, digit,
      punctuation mark or symbol, or a character Unicode has not yet assigned,
      such as an emoji newer than the patterns know;
    * `:marks`: no more than six marks, such as accents, in a row, counted
      through the characters taken anywhere, so no letter carries a tower of
      them over the lines around it.

  Known and accepted: the characters taken anywhere draw nothing, so a reason
  can hold a little text that does not show (about 197 bytes at most), and a
  direction mark can change the order digits and the signs between them show
  in within that one reason. Each reason is drawn as its own block, so nothing
  outside it turns.

  Broken UTF-8 is refused before any other rule reads it, so a check never
  raises on it.
  """
  use Ash.Resource.Validation

  alias Regents.Keyfleet.Seasons.Errors.ReasonError

  @longest 500

  # The characters drawn as nothing, though Unicode files some of them as
  # letters or symbols.
  @nothing ~S"\p{DI}\x{2800}\x{1D159}"

  # Taken anywhere, as ordinary writing types them: the soft hyphen, the
  # zero-width space, non-joiner and joiner, the two direction marks, the
  # Arabic letter mark, the Mongolian vowel separator and the word joiner.
  @anywhere ~S"\x{00AD}\x{200B}-\x{200F}\x{061C}\x{180E}\x{2060}"

  # One line of ordinary text: no control, format or line-separating character,
  # and none drawn as nothing, but those taken anywhere and the variation
  # selectors and flag tags taken in their place.
  @plain ~r/
    \A(?:
      [^\p{Cc}\p{Cf}\p{Zl}\p{Zp}#{@nothing}]
      | [#{@anywhere}]
      | (?<=\p{Emoji}) [\x{FE0E}\x{FE0F}]
      | (?<=\p{Ideographic}) [\x{E0100}-\x{E01EF}]
      | (?<=\p{Mongolian}) (?<=\p{L}) [\x{180B}-\x{180D}\x{180F}]
      | (?<=[\p{L}\p{N}\p{P}\p{S}]) [\x{FE00}-\x{FE0D}]
      | (?<=\p{Cn}) (?<!\p{Noncharacter_Code_Point}) \p{Variation_Selector}
      | (?<=\x{1F3F4}) \x{E0067}\x{E0062}
        (?:\x{E0065}\x{E006E}\x{E0067} | \x{E0073}\x{E0063}\x{E0074} | \x{E0077}\x{E006C}\x{E0073})
        \x{E007F}
    )*+\z
  /ux

  # A character that shows. `:plain` has already refused every character drawn
  # as nothing but those it lets through, and none of those is a letter, digit,
  # punctuation mark, symbol or unassigned, so none is taken here for one.
  @shows ~r/[\p{L}\p{N}\p{P}\p{S}] | (?!\p{Noncharacter_Code_Point})\p{Cn}/ux

  # Seven marks with nothing but characters taken anywhere between them. No mark
  # is one of those, so each run between two marks is read once and never given
  # back (`*+`), and the search stays linear however many stand between.
  @tower ~r/\p{M} (?:[#{@anywhere}]*+ \p{M}){6}/ux

  @doc "The most UTF-16 units a reason holds."
  def longest, do: @longest

  @impl true
  def validate(changeset, _opts, _context) do
    case broken(Ash.Changeset.get_attribute(changeset, :reason)) do
      nil -> :ok
      rule -> {:error, ReasonError.exception(rule: rule)}
    end
  end

  defp broken(nil), do: nil

  defp broken(reason) do
    cond do
      not String.valid?(reason) -> :plain
      units(reason) > @longest -> :too_long
      not Regex.match?(@plain, reason) -> :plain
      not Regex.match?(@shows, reason) -> :blank
      Regex.match?(@tower, reason) -> :marks
      true -> nil
    end
  end

  defp units(reason), do: div(byte_size(:unicode.characters_to_binary(reason, :utf8, :utf16)), 2)
end
