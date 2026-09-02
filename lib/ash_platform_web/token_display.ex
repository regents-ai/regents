defmodule AshPlatformWeb.TokenDisplay do
  @moduledoc """
  How the Stake, Redeem and Account pages write a figure.

  A token amount is written to four significant digits with a thousand,
  million, billion or trillion suffix: 9.76k, 101.4k, 76.75 million,
  1.044 billion. USDC is money and is always written in full to two decimals
  with thousands separators: 10,432.12. Digits beyond what is shown are
  dropped, never rounded up, so a figure never says more than the position
  behind it. A count such as a block number is a whole number with separators.
  Wherever a figure was shortened, the exact figure stays readable to
  assistive technology and on hover.
  """
  use Phoenix.Component

  @significant_digits 4
  @scales [
    {Decimal.new(1_000_000_000_000), " trillion"},
    {Decimal.new(1_000_000_000), " billion"},
    {Decimal.new(1_000_000), " million"},
    {Decimal.new(1_000), "k"}
  ]

  attr :amount, :string, default: nil
  attr :unit, :string, default: nil

  @doc """
  A read-only figure. It is shortened on screen while the exact amount stays
  readable to assistive technology and on hover. Never an input.
  """
  def amount(%{amount: nil} = assigns) do
    ~H"""
    —
    """
  end

  def amount(assigns) do
    assigns
    |> assign(
      exact: assigns.amount |> delimit() |> with_unit(assigns.unit),
      shown: assigns.amount |> shown(assigns.unit) |> with_unit(assigns.unit)
    )
    |> figure()
  end

  defp figure(%{exact: same, shown: same} = assigns) do
    ~H"""
    {@exact}
    """
  end

  defp figure(assigns) do
    ~H"""
    <span aria-hidden="true" title={@exact}>{@shown}</span>
    <span class="visually-hidden">{@exact}</span>
    """
  end

  defp with_unit(figure, nil), do: figure
  defp with_unit(figure, unit), do: "#{figure} #{unit}"

  @doc "The figure as the page writes it: money for USDC, a compact amount otherwise."
  def shown(amount, "USDC"), do: money(amount)
  def shown(amount, _unit), do: compact(amount)

  @doc "A whole count such as a block number, with thousands separators."
  def count(value) when is_integer(value), do: value |> Integer.to_string() |> delimit()

  @doc """
  Money: always two decimals with thousands separators, as in 10,432.12. The
  third decimal is dropped, never rounded up, so a balance is never overstated.
  """
  def money(amount) do
    amount
    |> Decimal.new()
    |> Decimal.round(2, :down)
    |> Decimal.to_string(:normal)
    |> delimit()
  end

  @doc """
  A token amount to four significant digits, suffixed by its scale: 9.76k,
  10.45k, 101.4k, 76.75 million, 755.5 million, 1.044 billion. Trailing zeros
  are dropped, so 67,000 is 67k and 100,000,000,000 is 100 billion. The digits
  beyond the fourth are dropped, never rounded up: the figure shown is allowed
  to say less than the position, never more, so a customer who types exactly
  what they read is never refused for exceeding it.
  """
  def compact(amount) do
    rounded = amount |> Decimal.new() |> significant(@significant_digits)

    {scale, suffix} =
      Enum.find(@scales, {Decimal.new(1), ""}, fn {scale, _suffix} ->
        rounded |> Decimal.abs() |> Decimal.gte?(scale)
      end)

    rounded
    |> Decimal.div(scale)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
    |> Kernel.<>(suffix)
  end

  defp significant(%Decimal{coef: 0} = zero, _digits), do: zero

  # The exponent of the leading digit decides how many decimal places keep
  # exactly `digits` significant ones; a negative count drops whole digits.
  defp significant(%Decimal{coef: coef, exp: exp} = decimal, digits) do
    magnitude = exp + length(Integer.digits(coef)) - 1
    Decimal.round(decimal, digits - 1 - magnitude, :down)
  end

  # Only the whole part is grouped: 1234567.89 reads 1,234,567.89.
  defp delimit(figure) do
    case String.split(figure, ".", parts: 2) do
      [whole] -> group(whole)
      [whole, fraction] -> "#{group(whole)}.#{fraction}"
    end
  end

  defp group(whole), do: Regex.replace(~r/\B(?=(\d{3})+(?!\d))/, whole, ",")
end
