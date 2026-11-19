defmodule AgentEns.RecordKey do
  @moduledoc """
  ENSIP-25 text record key construction.
  """

  alias AgentEns.ERC7930
  alias AgentEns.Error

  @spec record_key(ERC7930.t(), String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def record_key(%ERC7930{} = registry, agent_id) when is_binary(agent_id) do
    case validate_agent_id(agent_id) do
      :ok -> {:ok, "agent-registration[#{ERC7930.to_hex(registry)}][#{agent_id}]"}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  @spec evm_record_key(non_neg_integer(), String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def evm_record_key(chain_id, registry, agent_id)
      when is_integer(chain_id) and chain_id >= 0 and is_integer(agent_id) and agent_id >= 0 do
    with {:ok, interop} <- ERC7930.evm(chain_id, registry) do
      record_key(interop, Integer.to_string(agent_id))
    end
  end

  @doc """
  Builds the ENSIP-25 record key for an agent on an EVM registry.

  Accepts the agent id either as a non-negative integer token id or as a
  string identifier. Any other agent id type returns an
  `{:invalid_agent_id_type, value}` error.
  """
  @spec for_agent(non_neg_integer(), String.t(), non_neg_integer() | String.t()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def for_agent(chain_id, registry, agent_id) when is_integer(agent_id) do
    evm_record_key(chain_id, registry, agent_id)
  end

  def for_agent(chain_id, registry, agent_id) when is_binary(agent_id) do
    with {:ok, interop} <- ERC7930.evm(chain_id, registry) do
      record_key(interop, agent_id)
    end
  end

  def for_agent(_chain_id, _registry, agent_id) do
    {:error, Error.new({:invalid_agent_id_type, agent_id})}
  end

  @spec validate_agent_id(String.t()) :: :ok | {:error, Error.t()}
  def validate_agent_id(agent_id) when is_binary(agent_id) do
    if String.contains?(agent_id, ["[", "]"]) do
      {:error, Error.new({:invalid_agent_id, agent_id})}
    else
      :ok
    end
  end
end
