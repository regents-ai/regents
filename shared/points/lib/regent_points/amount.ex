defmodule RegentPoints.Amount do
  @moduledoc "Display points the one Regent way without changing stored micro-points."

  # Stored amounts are whole micro-Points. Moving the decimal point six places is
  # exact at any size; `Decimal.div/2` would round past its 34-digit precision.
  # A whole number of Points shows no decimals: 35, not 35.00.
  def format(micro) when is_integer(micro),
    do:
      %{Decimal.new(micro) | exp: -6}
      |> RegentFormat.amount()
      |> String.replace_suffix(".00", "")
end
