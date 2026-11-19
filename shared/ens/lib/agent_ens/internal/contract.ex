defmodule AgentEns.Internal.Contract do
  @moduledoc false

  alias AgentEns.Error
  alias AgentEns.Internal.ABI

  @addr_interface_id "0x3b3b57de"
  @text_interface_id "0x59d1d43c"
  @contenthash_interface_id "0xbc1c58d1"
  @extended_resolver_interface_id "0x9061b923"

  @spec fetch_resolver(module(), String.t(), String.t(), binary()) ::
          {:ok, String.t() | nil} | {:error, Error.t()}
  def fetch_resolver(rpc, rpc_url, ens_registry, node) do
    with {:ok, data} <- ABI.encode_call("resolver(bytes32)", [{:bytes32, node}]),
         {:ok, result} <- rpc.eth_call(rpc_url, ens_registry, data),
         {:ok, resolver} <- ABI.decode_address(result) do
      case resolver do
        "0x0000000000000000000000000000000000000000" -> {:ok, nil}
        value -> {:ok, String.downcase(value)}
      end
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.new({:rpc_error, reason})}
    end
  end

  @spec fetch_text_record(module(), String.t(), String.t() | nil, binary(), String.t()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def fetch_text_record(_rpc, _rpc_url, nil, _node, _key), do: {:ok, ""}

  def fetch_text_record(rpc, rpc_url, resolver, node, key) do
    with {:ok, data} <-
           ABI.encode_call("text(bytes32,string)", [{:bytes32, node}, {:string, key}]),
         {:ok, result} <- rpc.eth_call(rpc_url, resolver, data),
         {:ok, value} <- ABI.decode_string(result) do
      {:ok, value}
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, {:rpc_call_failed, _} = reason} ->
        {:error, Error.new({:resolver_call_failed, reason})}

      {:error, reason} ->
        {:error, Error.new({:rpc_error, reason})}
    end
  end

  @spec fetch_name_record(module(), String.t(), String.t() | nil, binary()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def fetch_name_record(_rpc, _rpc_url, nil, _node), do: {:ok, ""}

  def fetch_name_record(rpc, rpc_url, resolver, node) do
    with {:ok, data} <- ABI.encode_call("name(bytes32)", [{:bytes32, node}]),
         {:ok, result} <- rpc.eth_call(rpc_url, resolver, data),
         {:ok, value} <- ABI.decode_string(result) do
      {:ok, value}
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, {:rpc_call_failed, _} = reason} ->
        {:error, Error.new({:resolver_call_failed, reason})}

      {:error, reason} ->
        {:error, Error.new({:rpc_error, reason})}
    end
  end

  @spec fetch_addr_record(module(), String.t(), String.t() | nil, binary()) ::
          {:ok, String.t() | nil} | {:error, Error.t()}
  def fetch_addr_record(_rpc, _rpc_url, nil, _node), do: {:ok, nil}

  def fetch_addr_record(rpc, rpc_url, resolver, node) do
    with {:ok, data} <- ABI.encode_call("addr(bytes32)", [{:bytes32, node}]),
         {:ok, result} <- rpc.eth_call(rpc_url, resolver, data),
         {:ok, value} <- ABI.decode_address(result) do
      case value do
        "0x0000000000000000000000000000000000000000" -> {:ok, nil}
        _ -> {:ok, String.downcase(value)}
      end
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, {:rpc_call_failed, _} = reason} ->
        {:error, Error.new({:resolver_call_failed, reason})}

      {:error, reason} ->
        {:error, Error.new({:rpc_error, reason})}
    end
  end

  @spec fetch_contenthash(module(), String.t(), String.t() | nil, binary()) ::
          {:ok, String.t() | nil} | {:error, Error.t()}
  def fetch_contenthash(_rpc, _rpc_url, nil, _node), do: {:ok, nil}

  def fetch_contenthash(rpc, rpc_url, resolver, node) do
    with {:ok, data} <- ABI.encode_call("contenthash(bytes32)", [{:bytes32, node}]),
         {:ok, result} <- rpc.eth_call(rpc_url, resolver, data),
         {:ok, value} <- ABI.decode_bytes(result) do
      case value do
        <<>> -> {:ok, nil}
        binary -> {:ok, "0x" <> Base.encode16(binary, case: :lower)}
      end
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, {:rpc_call_failed, _} = reason} ->
        {:error, Error.new({:resolver_call_failed, reason})}

      {:error, reason} ->
        {:error, Error.new({:rpc_error, reason})}
    end
  end

  @spec fetch_registry_owner(module(), String.t(), String.t(), binary()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def fetch_registry_owner(rpc, rpc_url, ens_registry, node) do
    with {:ok, data} <- ABI.encode_call("owner(bytes32)", [{:bytes32, node}]),
         {:ok, result} <- rpc.eth_call(rpc_url, ens_registry, data),
         {:ok, owner} <- ABI.decode_address(result) do
      {:ok, String.downcase(owner)}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.new({:rpc_error, reason})}
    end
  end

  @spec fetch_wrapped_owner(module(), String.t(), String.t(), binary()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def fetch_wrapped_owner(rpc, rpc_url, name_wrapper, node) do
    token_id = :binary.decode_unsigned(node)

    with {:ok, data} <- ABI.encode_call("ownerOf(uint256)", [{:uint256, token_id}]),
         {:ok, result} <- rpc.eth_call(rpc_url, name_wrapper, data),
         {:ok, owner} <- ABI.decode_address(result) do
      {:ok, String.downcase(owner)}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.new({:wrapped_name_owner_lookup_failed, reason})}
    end
  end

  @spec fetch_ttl(module(), String.t(), String.t(), binary()) ::
          {:ok, non_neg_integer()} | {:error, Error.t()}
  def fetch_ttl(rpc, rpc_url, ens_registry, node) do
    with {:ok, data} <- ABI.encode_call("ttl(bytes32)", [{:bytes32, node}]),
         {:ok, result} <- rpc.eth_call(rpc_url, ens_registry, data),
         {:ok, ttl} <- ABI.decode_uint256(result) do
      {:ok, ttl}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.new({:rpc_error, reason})}
    end
  end

  @spec record_exists?(module(), String.t(), String.t(), binary()) ::
          {:ok, boolean()} | {:error, Error.t()}
  def record_exists?(rpc, rpc_url, ens_registry, node) do
    with {:ok, data} <- ABI.encode_call("recordExists(bytes32)", [{:bytes32, node}]),
         {:ok, result} <- rpc.eth_call(rpc_url, ens_registry, data),
         {:ok, exists?} <- ABI.decode_bool(result) do
      {:ok, exists?}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.new({:rpc_error, reason})}
    end
  end

  @spec supports_addr?(module(), String.t(), String.t()) :: {:ok, boolean()} | {:error, Error.t()}
  def supports_addr?(rpc, rpc_url, resolver) do
    supports_interface?(rpc, rpc_url, resolver, @addr_interface_id)
  end

  @spec supports_text?(module(), String.t(), String.t()) ::
          {:ok, boolean()} | {:error, Error.t()}
  def supports_text?(rpc, rpc_url, resolver) do
    supports_interface?(rpc, rpc_url, resolver, @text_interface_id)
  end

  @spec supports_contenthash?(module(), String.t(), String.t()) ::
          {:ok, boolean()} | {:error, Error.t()}
  def supports_contenthash?(rpc, rpc_url, resolver) do
    supports_interface?(rpc, rpc_url, resolver, @contenthash_interface_id)
  end

  @spec supports_extended_resolver?(module(), String.t(), String.t()) ::
          {:ok, boolean()} | {:error, Error.t()}
  def supports_extended_resolver?(rpc, rpc_url, resolver) do
    supports_interface?(rpc, rpc_url, resolver, @extended_resolver_interface_id)
  end

  @spec fetch_token_owner(module(), String.t(), String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def fetch_token_owner(rpc, rpc_url, registry_address, agent_id) do
    with {:ok, data} <- ABI.encode_call("ownerOf(uint256)", [{:uint256, agent_id}]),
         {:ok, result} <- rpc.eth_call(rpc_url, registry_address, data),
         {:ok, owner} <- ABI.decode_address(result) do
      {:ok, String.downcase(owner)}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.new({:rpc_error, reason})}
    end
  end

  @spec fetch_token_uri(module(), String.t(), String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def fetch_token_uri(rpc, rpc_url, registry_address, agent_id) do
    with {:ok, data} <- ABI.encode_call("tokenURI(uint256)", [{:uint256, agent_id}]),
         {:ok, result} <- rpc.eth_call(rpc_url, registry_address, data),
         {:ok, uri} <- ABI.decode_string(result) do
      {:ok, uri}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.new({:rpc_error, reason})}
    end
  end

  @spec fetch_token_approval(module(), String.t(), String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def fetch_token_approval(rpc, rpc_url, registry_address, agent_id) do
    with {:ok, data} <- ABI.encode_call("getApproved(uint256)", [{:uint256, agent_id}]),
         {:ok, result} <- rpc.eth_call(rpc_url, registry_address, data),
         {:ok, approval} <- ABI.decode_address(result) do
      {:ok, String.downcase(approval)}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.new({:rpc_error, reason})}
    end
  end

  @spec approved_for_all?(module(), String.t(), String.t(), String.t(), String.t()) ::
          {:ok, boolean()} | {:error, Error.t()}
  def approved_for_all?(rpc, rpc_url, registry_address, owner, operator) do
    with {:ok, data} <-
           ABI.encode_call(
             "isApprovedForAll(address,address)",
             [{:address, owner}, {:address, operator}]
           ),
         {:ok, result} <- rpc.eth_call(rpc_url, registry_address, data),
         {:ok, value} <- ABI.decode_bool(result) do
      {:ok, value}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.new({:rpc_error, reason})}
    end
  end

  defp supports_interface?(rpc, rpc_url, contract, interface_id) do
    with {:ok, data} <- ABI.encode_call("supportsInterface(bytes4)", [{:bytes4, interface_id}]),
         {:ok, result} <- rpc.eth_call(rpc_url, contract, data),
         {:ok, supported?} <- ABI.decode_bool(result) do
      {:ok, supported?}
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, {:rpc_call_failed, _} = reason} ->
        {:error, Error.new({:resolver_call_failed, reason})}

      {:error, reason} ->
        {:error, Error.new({:rpc_error, reason})}
    end
  end
end
