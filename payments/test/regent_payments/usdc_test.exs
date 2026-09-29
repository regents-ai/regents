defmodule RegentPayments.USDCTest do
  @moduledoc """
  A written amount is read as whole millionths exactly, or refused; it is
  never rounded, because a rounded payment is a different payment.
  """

  use ExUnit.Case, async: true

  alias RegentPayments.USDC

  test "a plain decimal of at most six places reads exactly and writes back" do
    for {written, atomic} <- [
          {"0", 0},
          {"2", 2_000_000},
          {"2.00", 2_000_000},
          {"0.10", 100_000},
          {"0.000001", 1},
          {"9999999.999999", 9_999_999_999_999}
        ] do
      assert USDC.parse(written) == {:ok, atomic}
    end

    assert USDC.format(100_000) == "0.10"
    assert USDC.format(1) == "0.000001"
    assert {:ok, 12_345_670} = USDC.parse(USDC.format(12_345_670))
  end

  test "anything that would need rounding or is not a plain decimal is refused" do
    for written <- [
          "0.0000001",
          "-1",
          "+1",
          "1e6",
          "1.",
          ".5",
          " 1",
          "1,00",
          "10000000",
          "",
          1,
          1.5,
          nil
        ] do
      assert USDC.parse(written) == :error
    end
  end
end
