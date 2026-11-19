defmodule AgentEns.Tx do
  @moduledoc """
  Builders for unsigned ENS, reverse-name, subname, and ERC-8004 requests.

  Use this module when you already know exactly which ENS change you want to
  make and you want a wallet-ready request for it.

  Common jobs in this module include:

  - setting text records
  - setting the ETH address
  - setting the content hash
  - changing the resolver
  - changing TTL
  - creating or updating subnames
  - setting the reverse name
  - updating the ERC-8004 registration URI

  Every builder returns `%AgentEns.TxRequest{}` on success. The package does
  not ask for approval or send the request.
  """

  alias AgentEns.Error
  alias AgentEns.Internal.ABI
  alias AgentEns.Internal.Validation
  alias AgentEns.Networks
  alias AgentEns.Normalize
  alias AgentEns.RecordKey
  alias AgentEns.TxRequest
  alias AgentEns.Verify

  @uint32_max 4_294_967_295
  @uint64_max 18_446_744_073_709_551_615
  @prepared_request_ttl_seconds 15 * 60

  @spec build_set_text_tx(map()) :: {:ok, TxRequest.t()} | {:error, Error.t()}
  def build_set_text_tx(params) when is_map(params) do
    with {:ok, chain_id} <- Validation.required_integer(params, :chain_id),
         {:ok, record_chain_id} <- Validation.optional_integer(params, :record_chain_id, chain_id),
         {:ok, registry_address} <- required_address(params, :registry_address),
         {:ok, agent_id} <- Validation.required_agent_id(params),
         {:ok, key} <- RecordKey.for_agent(record_chain_id, registry_address, agent_id) do
      build_set_text_record_tx(%{
        ens_name: Map.get(params, :ens_name),
        chain_id: chain_id,
        resolver_address: Map.get(params, :resolver_address),
        key: key,
        value: Map.get(params, :value) || "1"
      })
    end
  end

  @spec build_regent_subname_upgrade_tx(map()) :: {:ok, TxRequest.t()} | {:error, Error.t()}
  def build_regent_subname_upgrade_tx(params) when is_map(params) do
    with {:ok, chain_id} <- Validation.required_integer(params, :chain_id),
         {:ok, registrar_address} <- required_address(params, :registrar_address),
         {:ok, label} <- required_label(params),
         {:ok, owner_address} <- required_address(params, :owner_address),
         {:ok, resolver_address} <- required_address(params, :resolver_address),
         {:ok, data} <-
           ABI.encode_call("upgradeClaim(string,address,address)", [
             {:string, label},
             {:address, owner_address},
             {:address, resolver_address}
           ]) do
      {:ok,
       tx_request(
         registrar_address,
         chain_id,
         data,
         "Upgrade #{label}.regent.eth to an onchain Regent ENS name",
         params
       )}
    end
  end

  @spec build_regent_ensip25_link_tx(map()) :: {:ok, TxRequest.t()} | {:error, Error.t()}
  def build_regent_ensip25_link_tx(params) when is_map(params) do
    with {:ok, chain_id} <- Validation.required_integer(params, :chain_id),
         {:ok, registrar_address} <- required_address(params, :registrar_address),
         {:ok, label} <- required_label(params),
         {:ok, registry_chain_id} <- Validation.required_integer(params, :registry_chain_id),
         {:ok, registry_address} <- required_address(params, :registry_address),
         {:ok, agent_id} <- Validation.required_agent_id(params),
         {:ok, key} <- RecordKey.for_agent(registry_chain_id, registry_address, agent_id),
         {:ok, value} <- required_or_empty(params, :value),
         {:ok, data} <-
           ABI.encode_call("setAgentRegistrationText(string,string,string)", [
             {:string, label},
             {:string, key},
             {:string, value}
           ]) do
      {:ok,
       tx_request(
         registrar_address,
         chain_id,
         data,
         "Write ENSIP-25 proof for #{label}.regent.eth through the Regent registrar",
         params
       )}
    end
  end

  @spec build_regent_addr_tx(map()) :: {:ok, TxRequest.t()} | {:error, Error.t()}
  def build_regent_addr_tx(params) when is_map(params) do
    with {:ok, chain_id} <- Validation.required_integer(params, :chain_id),
         {:ok, registrar_address} <- required_address(params, :registrar_address),
         {:ok, label} <- required_label(params),
         {:ok, target_address} <- required_address(params, :address),
         {:ok, data} <-
           ABI.encode_call("setAddr(string,address)", [
             {:string, label},
             {:address, target_address}
           ]) do
      {:ok,
       tx_request(
         registrar_address,
         chain_id,
         data,
         "Set the ETH address for #{label}.regent.eth through the Regent registrar",
         params
       )}
    end
  end

  @spec build_set_text_record_tx(map()) :: {:ok, TxRequest.t()} | {:error, Error.t()}
  def build_set_text_record_tx(params) when is_map(params) do
    with {:ok, ens_name} <- Validation.required_binary(params, :ens_name),
         {:ok, chain_id} <- Validation.required_integer(params, :chain_id),
         {:ok, resolver_address} <- required_address(params, :resolver_address),
         {:ok, key} <- Validation.required_binary(params, :key),
         {:ok, value} <- required_or_empty(params, :value),
         {:ok, normalized_name} <- Normalize.normalize(ens_name),
         {:ok, node} <- Verify.namehash(normalized_name),
         {:ok, data} <-
           ABI.encode_call(
             "setText(bytes32,string,string)",
             [{:bytes32, node}, {:string, key}, {:string, value}]
           ) do
      {:ok,
       tx_request(
         resolver_address,
         chain_id,
         data,
         "Set ENS text record #{inspect(key)} on #{normalized_name}",
         params
       )}
    end
  end

  @spec build_set_addr_tx(map()) :: {:ok, TxRequest.t()} | {:error, Error.t()}
  def build_set_addr_tx(params) when is_map(params) do
    with {:ok, ens_name} <- Validation.required_binary(params, :ens_name),
         {:ok, chain_id} <- Validation.required_integer(params, :chain_id),
         {:ok, resolver_address} <- required_address(params, :resolver_address),
         {:ok, target_address} <- required_address(params, :address),
         {:ok, normalized_name} <- Normalize.normalize(ens_name),
         {:ok, node} <- Verify.namehash(normalized_name),
         {:ok, data} <-
           ABI.encode_call("setAddr(bytes32,address)", [
             {:bytes32, node},
             {:address, target_address}
           ]) do
      {:ok,
       tx_request(
         resolver_address,
         chain_id,
         data,
         "Set the ETH address for #{normalized_name}",
         params
       )}
    end
  end

  @spec build_set_contenthash_tx(map()) :: {:ok, TxRequest.t()} | {:error, Error.t()}
  def build_set_contenthash_tx(params) when is_map(params) do
    with {:ok, ens_name} <- Validation.required_binary(params, :ens_name),
         {:ok, chain_id} <- Validation.required_integer(params, :chain_id),
         {:ok, resolver_address} <- required_address(params, :resolver_address),
         {:ok, contenthash} <- required_bytes(params, :contenthash),
         {:ok, normalized_name} <- Normalize.normalize(ens_name),
         {:ok, node} <- Verify.namehash(normalized_name),
         {:ok, data} <-
           ABI.encode_call("setContenthash(bytes32,bytes)", [
             {:bytes32, node},
             {:bytes, contenthash}
           ]) do
      {:ok,
       tx_request(
         resolver_address,
         chain_id,
         data,
         "Set the content hash for #{normalized_name}",
         params
       )}
    end
  end

  @spec build_set_resolver_tx(map()) :: {:ok, TxRequest.t()} | {:error, Error.t()}
  def build_set_resolver_tx(params) when is_map(params) do
    with {:ok, ens_name} <- Validation.required_binary(params, :ens_name),
         {:ok, chain_id} <- Validation.required_integer(params, :chain_id),
         {:ok, new_resolver_address} <- required_address(params, :new_resolver_address),
         {:ok, {control, control_contract}} <- control_contract(params, chain_id),
         {:ok, normalized_name} <- Normalize.normalize(ens_name),
         {:ok, node} <- Verify.namehash(normalized_name),
         {:ok, data} <-
           ABI.encode_call("setResolver(bytes32,address)", [
             {:bytes32, node},
             {:address, new_resolver_address}
           ]) do
      {:ok,
       tx_request(
         control_contract,
         chain_id,
         data,
         "Update the resolver for #{normalized_name} through #{control_label(control)}",
         params
       )}
    end
  end

  @spec build_set_ttl_tx(map()) :: {:ok, TxRequest.t()} | {:error, Error.t()}
  def build_set_ttl_tx(params) when is_map(params) do
    with {:ok, ens_name} <- Validation.required_binary(params, :ens_name),
         {:ok, chain_id} <- Validation.required_integer(params, :chain_id),
         {:ok, ttl} <- required_uint64(params, :ttl),
         {:ok, {control, control_contract}} <- control_contract(params, chain_id),
         {:ok, normalized_name} <- Normalize.normalize(ens_name),
         {:ok, node} <- Verify.namehash(normalized_name),
         {:ok, data} <-
           ABI.encode_call("setTTL(bytes32,uint64)", [{:bytes32, node}, {:uint256, ttl}]) do
      {:ok,
       tx_request(
         control_contract,
         chain_id,
         data,
         "Update the TTL for #{normalized_name} through #{control_label(control)}",
         params
       )}
    end
  end

  @spec build_set_record_tx(map()) :: {:ok, TxRequest.t()} | {:error, Error.t()}
  def build_set_record_tx(params) when is_map(params) do
    with {:ok, ens_name} <- Validation.required_binary(params, :ens_name),
         {:ok, chain_id} <- Validation.required_integer(params, :chain_id),
         {:ok, owner_address} <- required_address(params, :owner_address),
         {:ok, resolver_address} <- required_address(params, :resolver_address),
         {:ok, ttl} <- required_uint64(params, :ttl),
         {:ok, {control, control_contract}} <- control_contract(params, chain_id),
         {:ok, normalized_name} <- Normalize.normalize(ens_name),
         {:ok, node} <- Verify.namehash(normalized_name),
         {:ok, data} <-
           ABI.encode_call("setRecord(bytes32,address,address,uint64)", [
             {:bytes32, node},
             {:address, owner_address},
             {:address, resolver_address},
             {:uint256, ttl}
           ]) do
      {:ok,
       tx_request(
         control_contract,
         chain_id,
         data,
         "Update the owner, resolver, and TTL for #{normalized_name} through #{control_label(control)}",
         params
       )}
    end
  end

  @spec build_set_subnode_owner_tx(map()) :: {:ok, TxRequest.t()} | {:error, Error.t()}
  def build_set_subnode_owner_tx(params) when is_map(params) do
    with {:ok, parent_name} <- Validation.required_binary(params, :parent_name),
         {:ok, chain_id} <- Validation.required_integer(params, :chain_id),
         {:ok, label} <- required_label(params),
         {:ok, owner_address} <- required_address(params, :owner_address),
         {:ok, {control, control_contract}} <- control_contract(params, chain_id),
         {:ok, normalized_parent_name} <- Normalize.normalize(parent_name),
         {:ok, parent_node} <- Verify.namehash(normalized_parent_name),
         {:ok, data} <-
           encode_set_subnode_owner(control, parent_node, label, owner_address, params) do
      {:ok,
       tx_request(
         control_contract,
         chain_id,
         data,
         "Create or update #{label}.#{normalized_parent_name} through #{control_label(control)}",
         params
       )}
    end
  end

  @spec build_set_subnode_record_tx(map()) :: {:ok, TxRequest.t()} | {:error, Error.t()}
  def build_set_subnode_record_tx(params) when is_map(params) do
    with {:ok, parent_name} <- Validation.required_binary(params, :parent_name),
         {:ok, chain_id} <- Validation.required_integer(params, :chain_id),
         {:ok, label} <- required_label(params),
         {:ok, owner_address} <- required_address(params, :owner_address),
         {:ok, resolver_address} <- required_address(params, :resolver_address),
         {:ok, ttl} <- required_uint64(params, :ttl),
         {:ok, {control, control_contract}} <- control_contract(params, chain_id),
         {:ok, normalized_parent_name} <- Normalize.normalize(parent_name),
         {:ok, parent_node} <- Verify.namehash(normalized_parent_name),
         {:ok, data} <-
           encode_set_subnode_record(
             control,
             parent_node,
             label,
             owner_address,
             resolver_address,
             ttl,
             params
           ) do
      {:ok,
       tx_request(
         control_contract,
         chain_id,
         data,
         "Create or update #{label}.#{normalized_parent_name} with resolver settings through #{control_label(control)}",
         params
       )}
    end
  end

  @spec build_create_subname_tx(map()) :: {:ok, TxRequest.t()} | {:error, Error.t()}
  def build_create_subname_tx(params) when is_map(params) do
    case subname_record_mode(params) do
      :record ->
        build_set_subnode_record_tx(params)

      :owner_only ->
        build_set_subnode_owner_tx(params)

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  @spec build_set_agent_uri_tx(map()) :: {:ok, TxRequest.t()} | {:error, Error.t()}
  def build_set_agent_uri_tx(params) when is_map(params) do
    with {:ok, chain_id} <- Validation.required_integer(params, :chain_id),
         {:ok, registry_address} <- required_address(params, :registry_address),
         {:ok, agent_id} <- Validation.required_integer(params, :agent_id),
         {:ok, new_uri} <- Validation.required_binary(params, :new_uri),
         {:ok, data} <-
           ABI.encode_call(
             "setAgentURI(uint256,string)",
             [{:uint256, agent_id}, {:string, new_uri}]
           ) do
      {:ok,
       tx_request(
         registry_address,
         chain_id,
         data,
         "Update ERC-8004 registration URI for agent #{agent_id}",
         params
       )}
    end
  end

  @spec build_reverse_set_name_tx(map()) :: {:ok, TxRequest.t()} | {:error, Error.t()}
  def build_reverse_set_name_tx(params) when is_map(params) do
    with {:ok, chain_id} <- Validation.required_integer(params, :chain_id),
         {:ok, ens_name} <- required_or_empty(params, :ens_name),
         {:ok, normalized_name} <- normalize_or_empty_name(ens_name),
         {:ok, reverse_registrar} <- reverse_registrar(params, chain_id),
         {:ok, data} <- ABI.encode_call("setName(string)", [{:string, normalized_name}]) do
      {:ok,
       tx_request(
         reverse_registrar,
         chain_id,
         data,
         reverse_name_description(normalized_name),
         params
       )}
    end
  end

  defp encode_set_subnode_owner(:registry, parent_node, label, owner_address, _params) do
    labelhash = ExKeccak.hash_256(label)

    ABI.encode_call("setSubnodeOwner(bytes32,bytes32,address)", [
      {:bytes32, parent_node},
      {:bytes32, labelhash},
      {:address, owner_address}
    ])
  end

  defp encode_set_subnode_owner(:name_wrapper, parent_node, label, owner_address, params) do
    with {:ok, fuses} <- required_uint32(params, :fuses),
         {:ok, expiry} <- required_uint64(params, :expiry) do
      ABI.encode_call("setSubnodeOwner(bytes32,string,address,uint32,uint64)", [
        {:bytes32, parent_node},
        {:string, label},
        {:address, owner_address},
        {:uint256, fuses},
        {:uint256, expiry}
      ])
    end
  end

  defp encode_set_subnode_record(
         :registry,
         parent_node,
         label,
         owner_address,
         resolver_address,
         ttl,
         _params
       ) do
    labelhash = ExKeccak.hash_256(label)

    ABI.encode_call("setSubnodeRecord(bytes32,bytes32,address,address,uint64)", [
      {:bytes32, parent_node},
      {:bytes32, labelhash},
      {:address, owner_address},
      {:address, resolver_address},
      {:uint256, ttl}
    ])
  end

  defp encode_set_subnode_record(
         :name_wrapper,
         parent_node,
         label,
         owner_address,
         resolver_address,
         ttl,
         params
       ) do
    with {:ok, fuses} <- required_uint32(params, :fuses),
         {:ok, expiry} <- required_uint64(params, :expiry) do
      ABI.encode_call("setSubnodeRecord(bytes32,string,address,address,uint64,uint32,uint64)", [
        {:bytes32, parent_node},
        {:string, label},
        {:address, owner_address},
        {:address, resolver_address},
        {:uint256, ttl},
        {:uint256, fuses},
        {:uint256, expiry}
      ])
    end
  end

  defp tx_request(to, chain_id, data, description, params) do
    to = String.downcase(to)
    expected_signer = prepared_expected_signer(params)

    %TxRequest{
      to: to,
      data: data,
      value: "0x0",
      chain_id: chain_id,
      description: description,
      expected_signer: expected_signer,
      expires_at: prepared_expires_at(params),
      risk_copy: prepared_risk_copy(params),
      idempotency_key: prepared_idempotency_key(to, chain_id, data, expected_signer, params)
    }
  end

  defp prepared_expected_signer(params) do
    case Map.get(params, :expected_signer) do
      value when is_binary(value) and value != "" -> String.downcase(value)
      _value -> nil
    end
  end

  defp prepared_expires_at(params) do
    case Map.get(params, :expires_at) do
      value when is_binary(value) and value != "" ->
        value

      %DateTime{} = value ->
        DateTime.to_iso8601(value)

      _value ->
        DateTime.utc_now()
        |> DateTime.add(@prepared_request_ttl_seconds, :second)
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()
    end
  end

  defp prepared_risk_copy(params) do
    case Map.get(params, :risk_copy) do
      value when is_binary(value) and value != "" ->
        value

      _value ->
        "Only approve if the destination, network, and action match your request."
    end
  end

  defp prepared_idempotency_key(to, chain_id, data, expected_signer, params) do
    case Map.get(params, :idempotency_key) do
      value when is_binary(value) and value != "" ->
        value

      _value ->
        payload = Enum.join([to, chain_id, data, expected_signer || ""], "\0")
        "ens:tx:" <> Base.encode16(:crypto.hash(:sha256, payload), case: :lower)
    end
  end

  defp subname_record_mode(params) do
    resolver_address = Map.get(params, :resolver_address)
    ttl = Map.get(params, :ttl)

    case {present?(resolver_address), present?(ttl)} do
      {true, true} -> :record
      {false, false} -> :owner_only
      _ -> {:error, Error.new({:missing_required_input, "resolver_address and ttl"})}
    end
  end

  defp control_contract(params, chain_id) do
    case {control_type(params), explicit_control_contract(params)} do
      {{:ok, control}, contract} when is_binary(contract) and contract != "" ->
        with {:ok, normalized} <- normalize_address(contract) do
          {:ok, {control, normalized}}
        end

      {{:ok, :registry}, _contract} ->
        contract_from_network(params, chain_id, :ens_registry, :registry)

      {{:ok, :name_wrapper}, _contract} ->
        contract_from_network(params, chain_id, :name_wrapper, :name_wrapper)

      {{:error, %Error{} = error}, _contract} ->
        {:error, error}
    end
  end

  defp contract_from_network(params, chain_id, field, control) do
    value =
      Map.get(params, field) ||
        case Networks.get(chain_id) || %{} do
          network -> Map.get(network, field)
        end

    cond do
      not (is_binary(value) and value != "") ->
        {:error, Error.new({:missing_required_input, Atom.to_string(field)})}

      true ->
        with {:ok, normalized} <- normalize_address(value) do
          {:ok, {control, normalized}}
        end
    end
  end

  defp explicit_control_contract(params) do
    Map.get(params, :control_contract)
  end

  defp control_type(params) do
    case Map.get(params, :control) || :registry do
      :registry -> {:ok, :registry}
      :name_wrapper -> {:ok, :name_wrapper}
      value -> {:error, Error.new({:invalid_argument, "control", value})}
    end
  end

  defp control_label(:registry), do: "the ENS registry"
  defp control_label(:name_wrapper), do: "the ENS Name Wrapper"

  defp required_or_empty(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) -> {:ok, value}
      value -> {:error, Error.new({:missing_required_input, "#{key}: #{inspect(value)}"})}
    end
  end

  defp required_address(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> normalize_address(value)
      value -> {:error, Error.new({:missing_required_input, "#{key}: #{inspect(value)}"})}
    end
  end

  defp required_uint32(params, key), do: required_integer_in_range(params, key, @uint32_max)

  defp required_uint64(params, key), do: required_integer_in_range(params, key, @uint64_max)

  defp required_label(params) do
    with {:ok, value} <- Validation.required_binary(params, :label),
         {:ok, normalized} <- Normalize.normalize(value) do
      if String.contains?(normalized, ".") do
        {:error, Error.new({:invalid_argument, "label", value})}
      else
        {:ok, normalized}
      end
    end
  end

  defp required_bytes(params, key) do
    case Map.get(params, key) do
      "0x" <> encoded ->
        case Base.decode16(encoded, case: :mixed) do
          {:ok, binary} -> {:ok, binary}
          :error -> {:error, Error.new({:invalid_argument, Atom.to_string(key), "0x" <> encoded})}
        end

      value when is_binary(value) and value != "" ->
        {:ok, value}

      value ->
        {:error, Error.new({:missing_required_input, "#{key}: #{inspect(value)}"})}
    end
  end

  defp present?(value) when value in [nil, ""], do: false
  defp present?(_value), do: true

  defp reverse_registrar(params, chain_id) do
    case Map.get(params, :reverse_registrar) do
      value when is_binary(value) and value != "" ->
        normalize_address(value)

      _ ->
        case Networks.get(chain_id) do
          %{reverse_registrar: value} when is_binary(value) and value != "" ->
            normalize_address(value)

          _ ->
            {:error, Error.new({:unsupported_network, chain_id})}
        end
    end
  end

  defp required_integer_in_range(params, key, max_value) do
    with {:ok, value} <- Validation.required_integer(params, key),
         :ok <- validate_integer_range(key, value, max_value) do
      {:ok, value}
    end
  end

  defp validate_integer_range(_key, value, max_value) when value <= max_value, do: :ok

  defp validate_integer_range(key, value, _max_value) do
    {:error, Error.new({:invalid_argument, Atom.to_string(key), value})}
  end

  defp normalize_address(value) when is_binary(value) do
    case AgentEns.Address.normalize(value) do
      nil -> {:error, Error.new({:invalid_address, value})}
      normalized -> {:ok, normalized}
    end
  end

  defp normalize_or_empty_name(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:ok, ""}
      trimmed -> Normalize.normalize(trimmed)
    end
  end

  defp reverse_name_description(""), do: "Clear the reverse ENS primary name"

  defp reverse_name_description(normalized_name),
    do: "Set reverse ENS primary name to #{normalized_name}"
end
