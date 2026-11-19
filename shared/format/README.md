# RegentFormat

Shared display formatting helpers for Regent Elixir apps.

`RegentFormat` is the single home for null-safe display values, `0x`
address/hash truncation, decimal and currency rendering, timestamp
formatting, relative times, identity monograms, and the one rule for a name a
person or an agent picks (`RegentFormat.Name`) and for text written over several
lines (`RegentFormat.Text`). Every short address
takes one form, `0x1234..abcd`: `0x`, the first four and the last four
characters, joined by two full stops. Product copy, CSS tone classes, and
domain-specific labels stay in the consuming app.

## Usage

Add the path dependency:

```elixir
{:regent_format, path: "../elixir-utils/format"}
```

Then call the helpers directly, or alias the module where a shorter name
reads better in templates:

```elixir
alias RegentFormat, as: Format

Format.token_amount(41_450_907_949_459_360_601_917, 18)
#=> "41,450.90"

Format.amount(Decimal.new("0.000123456"))
#=> "0.000123"

Format.format_currency("1234.5", 2)
#=> "$1,234.50"

Format.short_address("0x1234567890abcdef1234567890abcdef1234abcd")
#=> "0x1234..abcd"

Format.relative_time(~U[2026-01-05 15:01:05Z], ~U[2026-01-05 15:04:05Z])
#=> "3 minutes ago"

Format.format_datetime("2026-01-05T15:04:05Z", :date, "Unknown")
#=> "Jan 5, 2026"
```

Every amount a page shows goes through `amount/1` or `token_amount/2`: two
decimals from 1 up, three significant digits below 1, never rounded up. They
are exact at any size, up to the largest token amount a chain holds.
`NaN` and `Infinity` are not amounts: `parse_decimal/1` returns `nil` for them,
so `format_currency/2` shows `"Unavailable"`. Inputs, copied values, API bodies
and transaction data keep the exact amount.

## Development

```sh
mix deps.get
mix check
```
