defmodule RegentsWeb.Autolaunch.UsdValue do
  @moduledoc """
  An amount's value in US dollars, written as every Regent page writes one.
  The prices come from the core (`Regents.Autolaunch.UsdRates`); this only
  writes the figure.
  """

  @doc "A dollar figure, such as `$1,234.50` or `$0.0123`, as every Regent page writes one."
  def dollars(%Decimal{sign: -1, coef: coef} = value) when coef != 0,
    do: "-" <> dollars(%{value | sign: 1})

  def dollars(value), do: "$" <> RegentFormat.amount(value)
end
