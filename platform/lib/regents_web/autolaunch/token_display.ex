defmodule RegentsWeb.Autolaunch.TokenDisplay do
  @moduledoc """
  A price as every Autolaunch page shows one: the number shortened the one way
  every Regent page shortens an amount (`RegentFormat.amount/1`), then its
  ticker.
  """
  use Phoenix.Component

  attr :amount, :string, default: nil
  attr :unit, :string, default: nil
  attr :fallback, :string, default: "No price yet"

  @doc """
  A read-only price, or `fallback` while there is none. An exact price can run
  to 96 decimal places, so the shown figure is also the one given to assistive
  technology.
  """
  def price(%{amount: amount} = assigns) when is_nil(amount) or amount == "" do
    ~H"""
    {@fallback}
    """
  end

  def price(assigns) do
    assigns = assign(assigns, :shown, short(assigns.amount))

    ~H"""
    <span class="figure"><span class="figure__value" data-count>{@shown}</span><.unit unit={@unit} /></span>
    """
  end

  # Only a plain finite decimal is a figure to shorten: digits, one optional
  # fraction, one optional leading minus. Decimal's parser would also take NaN,
  # Infinity and exponents. Exact Q96 prices carry up to 96 decimal places, far
  # past Decimal's default 34-digit parse limit, so the parse is unbounded.
  @plain_decimal ~r/\A-?(?:0|[1-9]\d*)(?:\.\d+)?\z/

  @doc """
  An amount as text: a plain decimal string or a Decimal through
  `RegentFormat.amount/1`; any other text as written.
  """
  def short(%Decimal{} = amount), do: RegentFormat.amount(amount)

  def short(amount) when is_binary(amount) do
    if Regex.match?(@plain_decimal, amount) do
      {decimal, ""} = Decimal.parse(amount, max_digits: :infinity)
      RegentFormat.amount(decimal)
    else
      amount
    end
  end

  defp unit(%{unit: nil} = assigns), do: ~H""

  defp unit(assigns) do
    ~H"""
    {" "}<span class="figure__unit">{@unit}</span>
    """
  end
end
