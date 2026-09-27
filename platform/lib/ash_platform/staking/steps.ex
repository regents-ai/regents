defmodule AshPlatform.Staking.Steps do
  @moduledoc """
  The wallet steps behind the Stake page's buttons, built on the server with
  `regent_chain` and pushed to the page before anyone presses.

  Every claim is always a step. Stake and unstake are steps once the amount is
  one the contract can take, and a stake for another address once that address
  is valid and its warning acknowledged. An exact approval comes first whenever
  the last reading does not show enough allowance for this wallet, including
  when the allowance could not be read.
  """

  alias AshPlatform.Staking.Actions
  alias AshPlatform.WalletActions.Abi
  alias RegentChain.{Address, Call, Review}

  @approve "approve(address,uint256)"
  @calls %{
    "stake" => "stake(uint256,address)",
    "unstake" => "unstake(uint256,address)",
    "claim_usdc" => "claimUSDC(address)",
    "claim_regent" => "claimRegent(address)",
    "claim_and_restake_regent" => "claimAndRestakeRegent()"
  }

  # Each call is proved against the pinned staking ABI the moment this module
  # compiles, so a signature that drifted from the deployed contract never
  # builds a step.
  @abi_path Path.expand("../../../contracts/abi/regent-revenue-staking.json", __DIR__)
  @external_resource @abi_path
  @abi @abi_path |> File.read!() |> Jason.decode!()
  @after_compile __MODULE__

  @doc false
  def __after_compile__(_env, _bytecode),
    do: Enum.each(Map.values(@calls), &Abi.declared!(@abi, "function", &1))

  @doc """
  The steps for `signer` from the form on screen: the chosen action, the amount
  as typed, and whether the stake goes to another address. The claims are
  always there.
  """
  def steps(signer, staking, form) do
    action_steps =
      case {Actions.parse_amount(form.amount), form.action} do
        {{:ok, amount}, "stake"} -> stake_steps(signer, staking, amount, form)
        {{:ok, amount}, "unstake"} -> [step("unstake", [amount, signer])]
        _no_amount -> []
      end

    action_steps ++ claim_steps(signer)
  end

  @doc """
  Where a stake goes: the signer's own position, or another address that is
  valid, is neither the zero address nor the staking contract, and whose warning
  the person acknowledged for exactly that address.
  """
  def receiver(%{for_other: false}), do: {:ok, :signer}

  def receiver(%{receiver: input} = form) do
    cond do
      other_address(input) == :error -> {:error, :receiver_invalid}
      acknowledged?(form) -> {:ok, other_address(input)}
      true -> {:error, :receiver_unacknowledged}
    end
  end

  @doc "The receiving address typed in, when it is one a stake may go to."
  def other_address(input) do
    with {:ok, address} <- Address.normalize(String.trim(input)),
         false <- Address.equal?(address, Abi.staking_address()) do
      address
    else
      _refused -> :error
    end
  end

  @doc "Whether the warning is acknowledged for exactly the receiving address shown."
  def acknowledged?(%{for_other: true, receiver: input, acknowledged: acknowledged}),
    do: is_binary(acknowledged) and other_address(input) == acknowledged

  def acknowledged?(_form), do: false

  defp stake_steps(signer, staking, amount, form) do
    case receiver(form) do
      {:ok, receiver} ->
        stake = step("stake", [amount, if(receiver == :signer, do: signer, else: receiver)])
        if approval_needed?(staking, signer, amount), do: [approval(amount), stake], else: [stake]

      {:error, _unready} ->
        []
    end
  end

  defp claim_steps(signer),
    do: [
      step("claim_usdc", [signer]),
      step("claim_regent", [signer]),
      step("claim_and_restake_regent", [])
    ]

  defp step(name, arguments),
    do: Review.step(name, Abi.staking_address(), Call.encode(Map.fetch!(@calls, name), arguments))

  defp approval(amount),
    do:
      Review.step(
        "approve",
        Abi.stake_token_address(),
        Call.encode(@approve, [Abi.staking_address(), amount])
      )

  # The allowance on the page belongs to the wallet it was read for. Any other
  # wallet, and an allowance nobody could read, asks for the approval first.
  defp approval_needed?(
         %{wallet_address: wallet, wallet_stake_allowance_raw: raw},
         signer,
         amount
       )
       when is_binary(raw) do
    case {Address.equal?(wallet, signer), Integer.parse(raw)} do
      {true, {allowance, ""}} -> allowance < amount
      _unknown -> true
    end
  end

  defp approval_needed?(_staking, _signer, _amount), do: true
end
