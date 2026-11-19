defmodule RegentFormat do
  @moduledoc """
  Display formatting helpers shared across Regent Elixir apps.

  Covers null-safe display values, address/hash truncation, decimal and
  currency rendering, timestamp formatting, and short identity monograms.
  All functions are pure and return strings (or `nil` where documented);
  product-specific copy and CSS concerns stay in the consuming app.
  """

  alias Decimal, as: D

  @datetime_styles %{
    date: "%b %-d, %Y",
    time: "%H:%M UTC",
    datetime: "%b %-d, %Y %I:%M %p UTC",
    datetime_seconds: "%b %-d, %H:%M:%S UTC",
    short: "%b %-d"
  }

  @typedoc "A shared date and time presentation style."
  @type datetime_style :: :date | :time | :datetime | :datetime_seconds | :short

  @doc """
  Converts blank values to `nil`, passing everything else through.

      iex> RegentFormat.blank_to_nil("")
      nil

      iex> RegentFormat.blank_to_nil("ok")
      "ok"
  """
  @spec blank_to_nil(term()) :: term() | nil
  def blank_to_nil(nil), do: nil
  def blank_to_nil(""), do: nil
  def blank_to_nil(value), do: value

  @doc """
  Renders a value as a string, substituting `empty` for `nil` or `""`.

      iex> RegentFormat.display(nil)
      "-"

      iex> RegentFormat.display(42, "n/a")
      "42"
  """
  @spec display(term(), String.t()) :: String.t()
  def display(value, empty \\ "-")

  def display(nil, empty), do: empty
  def display("", empty), do: empty
  def display(value, _empty) when is_binary(value), do: value
  def display(value, _empty), do: to_string(value)

  @doc "Renders an unsigned integer value, with `\"n/a\"` for `nil`/blank."
  @spec display_uint(term()) :: String.t()
  def display_uint(value), do: display(value, "n/a")

  @doc "Renders an integer value, with `\"n/a\"` for `nil`/blank."
  @spec display_int(term()) :: String.t()
  def display_int(value), do: display(value, "n/a")

  @doc """
  Renders a duration in seconds, e.g. `"90 seconds"`, with `"n/a"` for `nil`.
  """
  @spec display_seconds(term()) :: String.t()
  def display_seconds(nil), do: "n/a"
  def display_seconds(value) when is_integer(value), do: Integer.to_string(value) <> " seconds"
  def display_seconds(value), do: to_string(value)

  @doc """
  Renders basis points as a percentage, e.g. `250` -> `"2.5%"`.

      iex> RegentFormat.display_bps_percent(250)
      "2.5%"
  """
  @spec display_bps_percent(term()) :: String.t()
  def display_bps_percent(nil), do: "n/a"
  def display_bps_percent(0), do: "n/a"

  def display_bps_percent(value) when is_integer(value) do
    %{D.new(value) | exp: -2}
    |> D.to_string(:normal)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
    |> Kernel.<>("%")
  end

  def display_bps_percent(value), do: to_string(value)

  @doc """
  Renders a unix timestamp as `"YYYY-MM-DD HH:MM:SS UTC"`, with `"n/a"` for
  `nil` or `0`.
  """
  @spec display_unix_timestamp(term()) :: String.t()
  def display_unix_timestamp(nil), do: "n/a"
  def display_unix_timestamp(0), do: "n/a"

  def display_unix_timestamp(value) when is_integer(value) and value > 0 do
    value
    |> DateTime.from_unix!()
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")
  rescue
    _ -> Integer.to_string(value)
  end

  def display_unix_timestamp(value), do: to_string(value)

  @doc """
  Renders an ISO8601 string as `"Jan 5, 2026 at 3:04 PM UTC"`, passing the
  input through when it cannot be parsed and returning `nil` for `nil`.
  """
  @spec display_datetime(String.t() | nil) :: String.t() | nil
  def display_datetime(nil), do: nil

  def display_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> Calendar.strftime(datetime, "%b %-d, %Y at %-I:%M %p UTC")
      _ -> value
    end
  end

  @doc """
  Renders a chart axis date as `"Jan 5, 2026"`, with `"Scheduled date"` for
  `nil` and pass-through for unparseable strings.
  """
  @spec display_chart_date(DateTime.t() | String.t() | nil) :: String.t()
  def display_chart_date(%DateTime{} = value), do: Calendar.strftime(value, "%b %-d, %Y")
  def display_chart_date(nil), do: "Scheduled date"

  def display_chart_date(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> Calendar.strftime(datetime, "%b %-d, %Y")
      _ -> value
    end
  end

  @doc """
  Parses an ISO8601 binary or passes through a `DateTime`; anything else
  (including unparseable strings) returns `nil`.
  """
  @spec parse_datetime(term()) :: DateTime.t() | nil
  def parse_datetime(%DateTime{} = value), do: value

  def parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  def parse_datetime(_value), do: nil

  @doc """
  Formats a `DateTime` or ISO8601 binary in one of the shared styles,
  returning `fallback` when the value cannot be parsed.

  Styles: `:date` (`"Jan 5, 2026"`), `:time` (`"15:04 UTC"`), `:datetime`
  (`"Jan 5, 2026 03:04 PM UTC"`), `:datetime_seconds`
  (`"Jan 5, 15:04:05 UTC"`), `:short` (`"Jan 5"`).

      iex> RegentFormat.format_datetime("2026-01-05T15:04:05Z", :date)
      "Jan 5, 2026"

      iex> RegentFormat.format_datetime("not a date", :time, "Unknown")
      "Unknown"
  """
  @spec format_datetime(DateTime.t() | String.t() | nil, datetime_style(), String.t() | nil) ::
          String.t() | nil
  def format_datetime(value, style, fallback \\ nil) when is_map_key(@datetime_styles, style) do
    case parse_datetime(value) do
      nil -> fallback
      datetime -> Calendar.strftime(datetime, Map.fetch!(@datetime_styles, style))
    end
  end

  @minute 60
  @hour 60 * @minute
  @day 24 * @hour
  @relative_units [
    {365 * @day, "year", "y"},
    {30 * @day, "month", "mo"},
    {7 * @day, "week", "w"},
    {@day, "day", "d"},
    {@hour, "hour", "h"},
    {@minute, "minute", "m"}
  ]

  @doc """
  Says how far `at` is from `now` the way a person would: `"just now"` within
  a minute either side, then the largest whole unit, `"3 minutes ago"` for the
  past and `"in 2 hours"` for the future. A month is thirty days and a year
  365. `now` is always passed in, so the answer depends only on its arguments.

      iex> RegentFormat.relative_time(~U[2026-01-05 15:01:05Z], ~U[2026-01-05 15:04:05Z])
      "3 minutes ago"

      iex> RegentFormat.relative_time(~U[2026-01-05 17:04:05Z], ~U[2026-01-05 15:04:05Z])
      "in 2 hours"
  """
  @spec relative_time(DateTime.t(), DateTime.t()) :: String.t()
  def relative_time(%DateTime{} = at, %DateTime{} = now) do
    seconds = DateTime.diff(at, now)

    case Enum.find(@relative_units, fn {size, _word, _short} -> abs(seconds) >= size end) do
      nil -> "just now"
      {size, word, _short} -> relative_words(div(abs(seconds), size), word, seconds < 0)
    end
  end

  @doc """
  `relative_time/2` in a few letters, for a narrow list: `"now"` within a minute,
  then the largest whole unit as `"3m"`, `"2h"`, `"5d"`, `"2w"`, `"4mo"` or `"1y"`,
  whichever side of `now` `at` is.
  """
  @spec short_relative_time(DateTime.t(), DateTime.t()) :: String.t()
  def short_relative_time(%DateTime{} = at, %DateTime{} = now) do
    seconds = abs(DateTime.diff(at, now))

    case Enum.find(@relative_units, fn {size, _word, _short} -> seconds >= size end) do
      nil -> "now"
      {size, _word, short} -> "#{div(seconds, size)}#{short}"
    end
  end

  defp relative_words(count, word, past?) do
    amount = "#{count} #{word}#{if count == 1, do: "", else: "s"}"
    if past?, do: amount <> " ago", else: "in " <> amount
  end

  @doc """
  Renders booleans as `"yes"`/`"no"`, with `"n/a"` for `nil`.
  """
  @spec yes_no(boolean() | nil) :: String.t()
  def yes_no(true), do: "yes"
  def yes_no(false), do: "no"
  def yes_no(nil), do: "n/a"

  @doc """
  Turns a snake_case key into capitalized words.

      iex> RegentFormat.humanize_key(:minimum_raise_quote)
      "Minimum Raise Quote"
  """
  @spec humanize_key(String.t() | atom()) :: String.t()
  def humanize_key(key) do
    key
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  @doc """
  Builds a one-or-two-letter monogram from a name, e.g. `"Helios Relay"` ->
  `"HR"`. A wallet name, a `0x` address in full or short form, takes the first
  two characters after `0x`. Returns `fallback` when no initials can be derived.

      iex> RegentFormat.monogram("Helios Relay", "AL")
      "HR"

      iex> RegentFormat.monogram("0x8f3c..41d2", "AL")
      "8F"

      iex> RegentFormat.monogram(nil, "AL")
      "AL"
  """
  @spec monogram(term(), String.t()) :: String.t()
  def monogram(name, fallback) when is_binary(name) do
    case Regex.run(~r/^\s*0x([0-9a-f]{2})/i, name) do
      [_, start] -> String.upcase(start)
      nil -> initials(name, fallback)
    end
  end

  def monogram(_name, fallback), do: fallback

  defp initials(name, fallback) do
    name
    |> String.split(~r/[\s-]+/, trim: true)
    |> Enum.map(&String.first/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(2)
    |> Enum.join()
    |> String.upcase()
    |> case do
      "" -> fallback
      initials -> initials
    end
  end

  @doc """
  Shortens a `0x` address to the one Regent short form: `0x`, the first four
  and the last four characters, joined by two full stops. `nil` stays `nil`,
  so a caller can say what a missing address means; any other value that is
  not a long `0x` string (an ENS name, a short code) is shown as it is.

      iex> RegentFormat.short_address("0x1234567890abcdef1234567890abcdef1234abcd")
      "0x1234..abcd"

      iex> RegentFormat.short_address("vault.eth")
      "vault.eth"
  """
  @spec short_address(String.t() | nil) :: String.t() | nil
  def short_address(nil), do: nil

  def short_address(<<"0x", head::binary-size(4), rest::binary>>) when byte_size(rest) > 4,
    do: "0x" <> head <> ".." <> binary_part(rest, byte_size(rest) - 4, 4)

  def short_address(value) when is_binary(value), do: value

  @doc """
  Truncates a `0x` hash to `"0x12345678…abcdef"`, substituting `empty` for
  `nil` and passing through values that are not long `0x` strings.
  """
  @spec short_hash(term(), String.t()) :: String.t()
  def short_hash(value, empty \\ "none")

  def short_hash(nil, empty), do: empty

  def short_hash("0x" <> _rest = value, _empty) when byte_size(value) > 14 do
    String.slice(value, 0, 10) <> "…" <> String.slice(value, -6, 6)
  end

  def short_hash(value, _empty), do: to_string(value)

  @doc """
  Parses integers, binaries, and `Decimal` structs into a `Decimal`, returning
  `nil` for blank or unparseable values and for `NaN` and `Infinity`, which are
  not amounts.

      iex> RegentFormat.parse_decimal("9.5E+2")
      Decimal.new("9.5E+2")

      iex> RegentFormat.parse_decimal("not a number")
      nil
  """
  @spec parse_decimal(term()) :: Decimal.t() | nil
  def parse_decimal(nil), do: nil
  def parse_decimal(""), do: nil
  def parse_decimal(value) when is_integer(value), do: D.new(value)
  def parse_decimal(%D{coef: coef} = value) when is_integer(coef), do: value

  def parse_decimal(value) when is_binary(value) do
    case D.parse(value) do
      {%D{coef: coef} = decimal, ""} when is_integer(coef) -> decimal
      _ -> nil
    end
  end

  def parse_decimal(_value), do: nil

  @doc """
  Renders a value as a dollar amount with thousands delimiters and a fixed
  number of decimal places, e.g. `"$1,234.50"`. Returns `"Unavailable"` for
  values that cannot be parsed.
  """
  @spec format_currency(term(), non_neg_integer()) :: String.t()
  def format_currency(nil, _places), do: "Unavailable"

  def format_currency(value, places) do
    case parse_decimal(value) do
      nil ->
        "Unavailable"

      decimal ->
        "$" <>
          (decimal
           |> to_places(places, :half_up)
           |> decimal_to_string(places)
           |> add_delimiters())
    end
  end

  @doc """
  Renders an amount for people to read, the one way every Regent page shows
  one. From 1 up: thousands grouped and exactly two decimals. Below 1: three
  significant digits. Zero is `"0"`. Digits past those shown are dropped, never
  rounded up, so a page never shows more than is there. Worked out exactly for
  a finite amount of any size.

  For display only: typed inputs, copied values, API and JSON bodies, agent
  tool results and transaction data keep the exact amount.

      iex> RegentFormat.amount(Decimal.new("41450.907949459360601917"))
      "41,450.90"

      iex> RegentFormat.amount(Decimal.new("0.000123456"))
      "0.000123"

      iex> RegentFormat.amount(5)
      "5.00"
  """
  @spec amount(Decimal.t() | integer()) :: String.t()
  def amount(value) when is_integer(value), do: amount(D.new(value))

  def amount(%D{sign: sign, coef: coef} = value) when is_integer(coef) do
    cond do
      coef == 0 -> "0"
      sign == -1 -> "-" <> amount(%{value | sign: 1})
      D.lt?(value, 1) -> value |> significant(3)
      true -> value |> to_places(2, :down) |> decimal_to_string(2) |> add_delimiters()
    end
  end

  @doc """
  `amount/1` for a token's whole-number amount (`atoms`) and its `decimals`,
  worked out exactly however large the amount is.

      iex> RegentFormat.token_amount(41_450_907_949_459_360_601_917, 18)
      "41,450.90"

      iex> RegentFormat.token_amount(500_000, 6)
      "0.500"
  """
  @spec token_amount(non_neg_integer(), non_neg_integer()) :: String.t()
  def token_amount(atoms, decimals)
      when is_integer(atoms) and atoms >= 0 and is_integer(decimals) and decimals >= 0,
      do: amount(D.new(1, atoms, -decimals))

  # A positive amount below 1 cut to `digits` significant digits.
  defp significant(%D{coef: coef, exp: exp} = value, digits) do
    leading = length(Integer.digits(coef)) + exp - 1
    places = digits - 1 - leading
    value |> to_places(places, :down) |> decimal_to_string(places)
  end

  # `value` at `places` decimal places, cut toward zero (`:down`) or rounded half
  # away from zero (`:half_up`). Worked out on the whole-number coefficient, so it
  # is exact at any size: `Decimal.round/3` stops at the context's 34 digits.
  defp to_places(%D{coef: coef, exp: exp} = value, places, _mode)
       when is_integer(coef) and exp >= -places,
       do: value

  defp to_places(%D{coef: coef, exp: exp} = value, places, mode) when is_integer(coef) do
    unit = Integer.pow(10, -exp - places)
    %{value | coef: div(coef + half(mode, unit), unit), exp: -places}
  end

  defp half(:down, _unit), do: 0
  defp half(:half_up, unit), do: div(unit, 2)

  @doc """
  Renders a `Decimal` in plain notation padded or truncated to `places`
  decimal places.
  """
  @spec decimal_to_string(Decimal.t(), non_neg_integer()) :: String.t()
  def decimal_to_string(decimal, 0),
    do: decimal |> to_places(0, :half_up) |> D.to_string(:normal)

  def decimal_to_string(decimal, places) do
    string = D.to_string(decimal, :normal)

    case String.split(string, ".", parts: 2) do
      [whole, fraction] ->
        padded =
          fraction
          |> String.pad_trailing(places, "0")
          |> String.slice(0, places)

        whole <> "." <> padded

      [whole] ->
        whole <> "." <> String.duplicate("0", places)
    end
  end

  @doc """
  Inserts comma thousands delimiters into a plain numeric string.

      iex> RegentFormat.add_delimiters("1234567.89")
      "1,234,567.89"
  """
  @spec add_delimiters(String.t()) :: String.t()
  def add_delimiters("-" <> rest), do: "-" <> add_delimiters(rest)

  def add_delimiters(value) do
    case String.split(value, ".", parts: 2) do
      [whole, fraction] -> add_delimiters_to_whole(whole) <> "." <> fraction
      [whole] -> add_delimiters_to_whole(whole)
    end
  end

  defp add_delimiters_to_whole(whole) do
    whole
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end
end
