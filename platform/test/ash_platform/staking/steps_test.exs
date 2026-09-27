defmodule AshPlatform.Staking.StepsTest do
  use ExUnit.Case, async: true

  alias AshPlatform.Staking.Steps

  @signer "0x1111111111111111111111111111111111111111"
  @other "0xde0B295669a9FD93d5F28D9Ec85E40f4cb697BAe"
  @staking "0xb027dc261636e30cbc0fe25b2f8e1ed273354ab5"
  @regent "0x6f89bca4ea5931edfcb09786267b251dee752b07"
  @one "1000000000000000000"

  # Calldata the page's browser code built for these same presses before the
  # server took over, byte for byte.
  @approve_one "0x095ea7b3000000000000000000000000b027dc261636e30cbc0fe25b2f8e1ed273354ab50000000000000000000000000000000000000000000000000de0b6b3a7640000"
  @stake_one "0x7acb77570000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000001111111111111111111111111111111111111111"
  @stake_one_for_other "0x7acb77570000000000000000000000000000000000000000000000000de0b6b3a7640000000000000000000000000000de0b295669a9fd93d5f28d9ec85e40f4cb697bae"
  @unstake_one "0x8381e1820000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000001111111111111111111111111111111111111111"

  defp form(overrides \\ %{}),
    do:
      Map.merge(
        %{action: "stake", amount: "1", for_other: false, receiver: "", acknowledged: nil},
        overrides
      )

  defp reading(allowance, wallet \\ @signer),
    do: %{wallet_address: wallet, wallet_stake_allowance_raw: allowance}

  defp steps(staking, form), do: Steps.review("regent-staking", @signer, staking, form).steps

  defp names(staking, form), do: Enum.map(steps(staking, form), & &1.step)

  test "a stake asks for its exact approval first unless this wallet's allowance covers it" do
    assert [
             %{step: "approve", to: @regent, data: @approve_one, value: "0x0"},
             %{step: "stake", to: @staking, data: @stake_one, value: "0x0"} | _claims
           ] = steps(reading("0"), form())

    assert names(reading(@one), form()) ==
             ~w(stake claim_usdc claim_regent claim_and_restake_regent)

    # Another wallet's allowance, and one nobody could read, ask for the approval.
    for staking <- [reading(@one, @other), reading(:unavailable), nil] do
      assert ["approve", "stake" | _claims] = names(staking, form())
    end
  end

  test "an unstake goes back to the signer and needs no approval" do
    assert [%{step: "unstake", to: @staking, data: @unstake_one} | _claims] =
             steps(reading("0"), form(%{action: "unstake"}))
  end

  test "every claim is a step whatever the reading or the amount says" do
    assert [
             %{
               step: "claim_usdc",
               data: "0x428526100000000000000000000000001111111111111111111111111111111111111111"
             },
             %{
               step: "claim_regent",
               data: "0x739c8d0d0000000000000000000000001111111111111111111111111111111111111111"
             },
             %{step: "claim_and_restake_regent", data: "0xe72a8732"}
           ] = steps(%{paused: true}, form(%{amount: ""}))

    for amount <- ["", "0", "-1", "1.0000000000000000001", "abc"] do
      assert names(nil, form(%{amount: amount})) ==
               ~w(claim_usdc claim_regent claim_and_restake_regent)
    end
  end

  test "a stake for someone else is a step only once that exact address is acknowledged" do
    acknowledged = Steps.other_address(@other)
    assert acknowledged == String.downcase(@other)

    assert [_approve, %{step: "stake", data: @stake_one_for_other} | _claims] =
             steps(nil, form(%{for_other: true, receiver: @other, acknowledged: acknowledged}))

    assert Steps.receiver(form(%{for_other: true, receiver: @other})) ==
             {:error, :receiver_unacknowledged}

    # An acknowledgment for one address says nothing about another.
    other_ack = form(%{for_other: true, receiver: @signer, acknowledged: acknowledged})
    assert Steps.receiver(other_ack) == {:error, :receiver_unacknowledged}
    refute "stake" in names(nil, other_ack)
  end

  test "a receiving address must be a plain address a stake may go to" do
    mistyped = String.replace(@other, "de0B", "De0B")

    for input <- [
          "",
          "vitalik.eth",
          "0x0000000000000000000000000000000000000000",
          @staking,
          String.upcase(@staking) |> String.replace("0X", "0x"),
          mistyped
        ] do
      assert Steps.other_address(input) == :error

      assert Steps.receiver(form(%{for_other: true, receiver: input})) ==
               {:error, :receiver_invalid}
    end

    assert Steps.receiver(form()) == {:ok, :signer}
  end

  test "the review carries the form it was built from" do
    review = Steps.review("regent-staking", @signer, nil, form(%{amount: "2"}))

    assert review.inputs == %{
             action: "stake",
             amount: "2",
             for_other: false,
             receiver: "",
             acknowledged: false
           }

    assert review.chain.chain_id == 8453
    assert review.signer == @signer
  end
end
