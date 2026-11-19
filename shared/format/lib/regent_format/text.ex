defmodule RegentFormat.Text do
  @moduledoc """
  The one rule for text a person or an agent writes over several lines, which shows
  on every Regent site: a message, a note or a chat with the assistant.

  Each line follows the rule for a name (`RegentFormat.Name`), so the text holds no
  hidden characters, and lines are separated by a line break (`\\n` or `\\r\\n`) or
  a tab.
  """

  @doc ~S"""
  The pattern a whole text matches, for an Ash `match:` validation.

      iex> Regex.match?(RegentFormat.Text.pattern(), "First line\r\n\tSecond 👩\u200D💻")
      true

      iex> Regex.match?(RegentFormat.Text.pattern(), "Ada\u202Egnp.exe\nok")
      false

      iex> Regex.match?(RegentFormat.Text.pattern(), "carriage\rreturn")
      false
  """
  @spec pattern() :: Regex.t()
  def pattern,
    do:
      ~r/\A(?:\r?\n|\t|\x{1F3F4}[\x{E0020}-\x{E007E}]+\x{E007F}|(?<=[^\p{Cc}\p{Cf}\p{Z}])[\x{200C}\x{200D}](?=[^\p{Cc}\p{Cf}\p{Z}])|[^\p{Cc}\p{Cf}\p{Zl}\p{Zp}])*\z/u
end
