defmodule AshPlatform.Redemption.StepsTest do
  use ExUnit.Case, async: true

  alias AshPlatform.Redemption.Steps

  @animata_i "0x78402119ec6349a0d41f12b54938de7bf783c923"
  @animata_ii "0x903c4c1e8b8532fbd3575482d942d493eb9266e2"
  @redeemer "0x71065b775a590c43933f10c0055dc7d74afabb0e"
  @usdc "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"

  # Calldata the page's browser code built for these same presses before the
  # server took over, byte for byte.
  @approve_nft "0xa22cb46500000000000000000000000071065b775a590c43933f10c0055dc7d74afabb0e0000000000000000000000000000000000000000000000000000000000000001"
  @approve_usdc "0x095ea7b300000000000000000000000071065b775a590c43933f10c0055dc7d74afabb0e0000000000000000000000000000000000000000000000000000000004c4b400"
  @redeem_42 "0x1e9a695000000000000000000000000078402119ec6349a0d41f12b54938de7bf783c923000000000000000000000000000000000000000000000000000000000000002a"
  @claim "0x4e71d92d"

  defp names(collection, token_id),
    do: Enum.map(Steps.steps(%{collection: collection, token_id: token_id}), & &1.step)

  test "a chosen Animata gives every step, each exact calldata to its own contract" do
    assert [
             %{step: "approve_nft_collection", to: @animata_i, data: @approve_nft, value: "0x0"},
             %{step: "approve_exact_usdc", to: @usdc, data: @approve_usdc, value: "0x0"},
             %{step: "redeem", to: @redeemer, data: @redeem_42, value: "0x0"},
             %{step: "claim", to: @redeemer, data: @claim, value: "0x0"}
           ] = Steps.steps(%{collection: "animata_i", token_id: "42"})

    assert [%{to: @animata_ii, data: @approve_nft} | _rest] =
             Steps.steps(%{collection: "animata_ii", token_id: "42"})
  end

  test "redeeming is a step only for a token ID from 1 to 999; the rest never depend on it" do
    for token_id <- ["1", "042", "999"],
        do: assert("redeem" in names("animata_i", token_id))

    for token_id <- ["", "0", "1000", "-1", "4.2", " 42", "abc"],
        do:
          assert(
            names("animata_i", token_id) == ~w(approve_nft_collection approve_exact_usdc claim)
          )

    assert names("animata_iii", "42") == ~w(approve_exact_usdc claim)
  end

  test "a token ID reads as the redeemer takes it" do
    assert Steps.token_id("042") == {:ok, 42}
    assert Steps.token_id("999") == {:ok, 999}
    assert Steps.token_id("1000") == :error
    assert Steps.token_id(nil) == :error
  end
end
