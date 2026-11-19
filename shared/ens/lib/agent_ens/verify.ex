defmodule AgentEns.Verify do
  @moduledoc """
  Simple ENSIP-25 verification helpers.

  Use this module when you only need to answer a narrow question:
  does this ENS name already contain the expected proof record?

  For richer inspection or planning, use `AgentEns.Read` or `AgentEns.Plan`.
  """

  alias AgentEns.Error
  alias AgentEns.Internal.Contract
  alias AgentEns.Internal.RPC
  alias AgentEns.Networks
  alias AgentEns.Normalize
  alias AgentEns.RecordKey

  @type verification_status :: :verified | :ens_record_missing

  @spec verified?(verification_status()) :: boolean()
  def verified?(:verified), do: true
  def verified?(_status), do: false

  @spec verify(
          String.t(),
          String.t(),
          non_neg_integer(),
          String.t(),
          non_neg_integer(),
          keyword()
        ) :: {:ok, verification_status()} | {:error, Error.t()}
  def verify(rpc_url, ens_name, chain_id, registry, agent_id, opts \\ [])
      when is_binary(rpc_url) and is_binary(ens_name) and is_integer(chain_id) and chain_id >= 0 and
             is_integer(agent_id) and agent_id >= 0 do
    rpc = Keyword.get(opts, :rpc_module, RPC)

    ens_registry =
      Keyword.get(opts, :ens_registry, default_ens_registry(chain_id))
      |> String.downcase()

    with {:ok, key} <- RecordKey.evm_record_key(chain_id, registry, agent_id),
         {:ok, node} <- namehash(ens_name),
         {:ok, resolver} <- Contract.fetch_resolver(rpc, rpc_url, ens_registry, node),
         {:ok, value} <- Contract.fetch_text_record(rpc, rpc_url, resolver, node, key) do
      if value == "", do: {:ok, :ens_record_missing}, else: {:ok, :verified}
    end
  end

  @spec verify_agent(String.t(), atom(), non_neg_integer(), String.t(), keyword()) ::
          {:ok, verification_status()} | {:error, Error.t()}
  def verify_agent(rpc_url, network, agent_id, ens_name, opts \\ [])
      when is_binary(rpc_url) and is_atom(network) and is_integer(agent_id) and agent_id >= 0 and
             is_binary(ens_name) do
    case network_mapping(network) do
      %{chain_id: chain_id, registry: registry} ->
        verify(rpc_url, ens_name, chain_id, String.downcase(registry), agent_id, opts)

      nil ->
        {:error, Error.new({:unsupported_network, network})}
    end
  end

  @spec namehash(String.t()) :: {:ok, binary()} | {:error, Error.t()}
  def namehash(name) when is_binary(name) do
    with {:ok, normalized} <- Normalize.normalize(name) do
      node =
        normalized
        |> String.split(".", trim: true)
        |> Enum.reverse()
        |> Enum.reduce(<<0::256>>, fn label, acc ->
          ExKeccak.hash_256(acc <> ExKeccak.hash_256(label))
        end)

      {:ok, node}
    end
  end

  defp default_ens_registry(chain_id) do
    case Networks.get(chain_id) do
      %{ens_registry: ens_registry} -> ens_registry
      _ -> "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e"
    end
  end

  defp network_mapping(:ethereum_mainnet) do
    %{chain_id: 1, registry: network_registry(1)}
  end

  defp network_mapping(:ethereum_sepolia) do
    %{chain_id: 11_155_111, registry: network_registry(11_155_111)}
  end

  defp network_mapping(_other), do: nil

  defp network_registry(chain_id) do
    case Networks.get(chain_id) do
      %{erc8004_registry: registry} -> registry
      _ -> nil
    end
  end
end
