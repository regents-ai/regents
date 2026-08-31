defmodule AshPlatform.TestRegentsClubChainClient do
  @moduledoc false

  alias AshPlatform.RegentsClub

  def readiness, do: response(:readiness, :ok)

  def status do
    response(:status, {:ok, %{state: :ready, base_uri: RegentsClub.old_base_uri()}})
  end

  def prepare do
    response(
      :prepare,
      {:ok,
       %{
         anchor: %{number: 42, hash: hash(42)},
         owner: RegentsClub.owner(),
         base_uri: RegentsClub.old_base_uri(),
         token_uris: %{
           first: RegentsClub.old_base_uri() <> "1",
           last: RegentsClub.old_base_uri() <> "1998"
         },
         total_supply: 1998,
         erc4906_supported: true,
         owner_simulation: "success",
         non_owner_simulation: "revert",
         runtime_keccak256: RegentsClub.runtime_keccak256(),
         gas_estimate: 81_189
       }}
    )
  end

  def observe(envelope, hash) do
    default =
      if String.starts_with?(hash, "0x" <> String.duplicate("de", 4)),
        do: {:ok, :reverted},
        else: {:ok, {:finalized, finalized(envelope, hash)}}

    response(:observe, default)
  end

  def recover(envelope) do
    response(:recover, {:ok, {:unknown, {envelope.arguments.attempt_id, :no_unique_match}}})
  end

  def media_readiness, do: response(:media_readiness, :ok)

  defp response(key, default) do
    :ash_platform
    |> Application.get_env(:test_regents_club_chain_responses, %{})
    |> Map.get(key, default)
    |> evaluate()
  end

  defp evaluate(fun) when is_function(fun, 0), do: fun.()
  defp evaluate(response), do: response

  defp finalized(envelope, transaction_hash) do
    %{
      transaction_hash: transaction_hash,
      block_number: 43,
      block_hash: hash(43),
      anchor_block_number: envelope.metadata.anchor_block_number,
      anchor_block_hash: envelope.metadata.anchor_block_hash,
      finality_block_number: 44,
      finality_block_hash: hash(44),
      base_uri: RegentsClub.new_base_uri(),
      token_uris: %{
        first: RegentsClub.new_base_uri() <> "1",
        last: RegentsClub.new_base_uri() <> "1998"
      }
    }
  end

  defp hash(number), do: "0x" <> String.pad_leading(Integer.to_string(number, 16), 64, "0")
end
