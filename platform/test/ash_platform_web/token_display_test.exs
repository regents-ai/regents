defmodule AshPlatformWeb.TokenDisplayTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias AshPlatformWeb.TokenDisplay

  defp amount(assigns), do: render_component(&TokenDisplay.amount/1, assigns)

  # The founder's rule, in his own examples: four significant digits, trailing
  # zeros dropped, k / million / billion. Never a tail of eighteen decimals.
  test "COMPACT_IS_FOUR_SIGNIFICANT_DIGITS" do
    for {value, expected} <- [
          {"9760", "9.76k"},
          {"10450", "10.45k"},
          {"101400", "101.4k"},
          {"76750000", "76.75 million"},
          {"755500000", "755.5 million"},
          {"1044000000", "1.044 billion"},
          {"7321632890.079463764963354621", "7.321 billion"},
          {"4958887696.28029413182457336", "4.958 billion"},
          {"128185.507825379036090931", "128.1k"},
          {"100000000000", "100 billion"},
          {"1500000000000", "1.5 trillion"},
          {"123456789012345.678", "123.4 trillion"},
          {"67000", "67k"},
          {"100", "100"},
          {"1.23456", "1.234"},
          {"0.5", "0.5"},
          {"0", "0"},
          {"0.000000000000000001", "0.000000000000000001"}
        ] do
      assert TokenDisplay.compact(value) == expected,
             "#{value} read #{TokenDisplay.compact(value)}"
    end
  end

  # Three significant digits, letter suffixes, trailing zeros dropped. Under a
  # thousand is a plain integer. Digits beyond the third are dropped.
  test "SHORT_IS_THREE_SIGNIFICANT_DIGITS" do
    for {value, expected} <- [
          {0, "0"},
          {510, "510"},
          {999, "999"},
          {510_000, "510k"},
          {999_499, "999k"},
          {1_000_000, "1m"},
          {1_040_000, "1.04m"},
          {1_400_000, "1.4m"},
          {12_300_000, "12.3m"}
        ] do
      assert TokenDisplay.short(value) == expected,
             "#{value} read #{TokenDisplay.short(value)}"
    end
  end

  # Display is allowed to say less than the position, never more: a customer
  # who types exactly the figure shown must never be refused for exceeding it.
  test "COMPACT_TRUNCATES_AND_NEVER_ROUNDS_A_BALANCE_UP" do
    for {value, expected} <- [
          {"999.96", "999.9"},
          {"999960", "999.9k"},
          {"999950000", "999.9 million"},
          {"7389999999.9", "7.389 billion"},
          {"999999999.999999999999999999", "999.9 million"},
          {"7390000000.123456789012345678", "7.39 billion"}
        ] do
      assert TokenDisplay.compact(value) == expected,
             "#{value} read #{TokenDisplay.compact(value)}"
    end
  end

  # USDC is money: always two decimals, always grouped, never shortened, and a
  # third decimal is dropped rather than rounded up.
  test "MONEY_IS_ALWAYS_TWO_DECIMALS" do
    for {value, expected} <- [
          {"103.030615", "103.03"},
          {"100.999999", "100.99"},
          {"0", "0.00"},
          {"10432.123", "10,432.12"},
          {"4.25", "4.25"},
          {"1.5", "1.50"},
          {"125000", "125,000.00"},
          {"7321632890.5", "7,321,632,890.50"}
        ] do
      assert TokenDisplay.money(value) == expected
    end
  end

  test "COUNTS_ARE_WHOLE_NUMBERS_WITH_SEPARATORS" do
    assert TokenDisplay.count(1_234) == "1,234"
    assert TokenDisplay.count(549) == "549"
    assert TokenDisplay.count(1_000_000) == "1,000,000"
  end

  # A figure already written in full is rendered once, as itself. Nothing is
  # hidden, shortened or duplicated for a screen reader.
  test "UNSHORTENED_FIGURES_ARE_RENDERED_EXACTLY_ONCE" do
    for {value, unit, expected} <- [
          {"10", "REGENT", "10 REGENT"},
          {"4.25", "USDC", "4.25 USDC"},
          {"100", nil, "100"},
          {"0.000000000000000001", "REGENT", "0.000000000000000001 REGENT"}
        ] do
      assert String.trim(amount(%{amount: value, unit: unit})) == expected
    end
  end

  # A shortened figure keeps the exact one in the page as real text rather than
  # as an attribute on a generic element, and on hover.
  test "SHORTENED_FIGURES_KEEP_THE_EXACT_ONE_READABLE" do
    html = amount(%{amount: "7321632890.079463764963354621", unit: "REGENT"})

    assert html =~
             ~s(<span aria-hidden="true" title="7,321,632,890.079463764963354621 REGENT">7.321 billion REGENT</span>)

    assert html =~
             ~s(<span class="visually-hidden">7,321,632,890.079463764963354621 REGENT</span>)

    usdc = amount(%{amount: "1.5", unit: "USDC"})
    assert usdc =~ ~s(<span aria-hidden="true" title="1.5 USDC">1.50 USDC</span>)
  end

  # A figure Base could not be read for is not a zero and not a blank.
  test "AN_UNREAD_AMOUNT_RENDERS_THE_DASH" do
    assert amount(%{amount: nil, unit: "REGENT"}) |> String.trim() == "—"
  end
end
