# Changelog

## Unreleased

- The tests are gone (19 Nov 2026), with StreamData. `mix check` compiles with
  warnings as errors and checks unused locks, formatting and the usage rules.
- `monogram/2` gives a wallet name, a `0x` address in full or short form, the
  first two characters after `0x` in capitals (`"0x8f3c..41d2"` -> `"8F"`). It
  gave `"0"`, so every wallet author's picture read 0.
- `RegentFormat.Text.pattern/0` is the one rule for text written over several
  lines, such as a message or a note: each line follows `RegentFormat.Name`, and
  lines are separated by a line break or a tab.
- `amount/1`, `token_amount/2`, `format_currency/2`, `decimal_to_string/2` and
  `display_bps_percent/1` are exact at any size. An amount of 1e32 or more, such
  as a bid at the largest price a chain allows, raised instead of showing, and a
  negative amount longer than 34 digits could show rounded up. They now work on
  the whole-number digits instead of Decimal's 34-digit precision.
  `parse_decimal/1` returns `nil` for `NaN` and `Infinity`, so `format_currency/2`
  shows `"Unavailable"` for them, and `amount/1` takes finite amounts only.
- `amount/1` and `token_amount/2` show every amount the one way (founder,
  2026-10-27): from 1 up, thousands grouped and two decimals; below 1, three
  significant digits; zero as `"0"`. Digits past those are dropped, never rounded
  up. `token_amount/2` works from a token's whole-number amount and decimals
  exactly, however large. For display only.
- Needs Elixir 1.20 on OTP 29 (`elixir: "~> 1.20"`), and its locked dependencies are
  updated to their newest allowed versions.
- `RegentFormat.Name.pattern/0` is the one rule for a name a person or an agent
  picks (founder, 2026-10-19): no control, line or paragraph separator, or
  format character, except a zero-width joiner or non-joiner between two visible
  characters and tag characters inside a complete flag. `regent_identity` and
  `regent_agents` use it.
- `short_relative_time/2` says the same as `relative_time/2` in a few letters,
  `"now"`, `"3m"`, `"2h"`, `"5d"`, `"2w"`, `"4mo"` or `"1y"`, for a narrow list.

## 0.2.0

- `short_address/1` is the one short form for an address, `0x1234..abcd`.
  It keeps `nil` as `nil` and shows other values as they are. `short_wallet/1`
  and the `empty` argument of `short_address/2` are gone: call
  `short_address/1`, and write `|| "..."` where a missing address needs words.
- `relative_time/2` says how far one moment is from another, `"3 minutes
  ago"` or `"in 2 hours"`, with `now` passed in.

## 0.1.0

- Initial release: display helpers, address/hash truncation, decimal and
  currency formatting, timestamp styles, and monograms promoted from
  `AutolaunchWeb.Format` and the autolaunch LiveViews.
