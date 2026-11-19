defmodule AgentEns.Read do
  @moduledoc """
  Read helpers for ENS names and subnames.

  This module is for inspection, not for making changes.

  Use `read_name/1` when you want to understand the current state of a name
  before you show a review screen or decide what to do next. The returned
  `NameDetails` struct can include:

  - the normalized name
  - whether the name exists
  - whether the name is wrapped
  - who controls it
  - which resolver it uses
  - which resolver features appear to be available
  - the current ETH address
  - the current content hash
  - selected text records
  - warnings about important edge cases

  This is the most useful module when you want to show a person what a name
  looks like right now.
  """

  alias AgentEns.Error
  alias AgentEns.Internal.Contract
  alias AgentEns.Internal.RPC
  alias AgentEns.Internal.Validation
  alias AgentEns.Networks
  alias AgentEns.Normalize
  alias AgentEns.Verify

  defmodule Input do
    @moduledoc """
    Input values used to read ENS name details.
    """

    @enforce_keys [:ens_name, :chain_id, :rpc_url]
    defstruct [
      :ens_name,
      :chain_id,
      :rpc_url,
      :rpc_module,
      :ens_registry,
      :name_wrapper,
      text_keys: [],
      include_address?: true,
      include_contenthash?: true
    ]

    @type t :: %__MODULE__{
            ens_name: String.t(),
            chain_id: non_neg_integer(),
            rpc_url: String.t(),
            rpc_module: module() | nil,
            ens_registry: String.t() | nil,
            name_wrapper: String.t() | nil,
            text_keys: [String.t()],
            include_address?: boolean(),
            include_contenthash?: boolean()
          }
  end

  defmodule NameDetails do
    @moduledoc """
    Read-only details gathered from the ENS registry, wrapper, and resolver.

    This struct is designed to be easy to display in a CLI or UI:

    - `manager` is the address that appears to control the name right now
    - `manager_source` tells you whether that control came from the registry or wrapper
    - `resolver_profiles` tells you which common resolver features appear to be present
    - `warnings` gives you plain text notes worth surfacing to a person
    """

    @enforce_keys [
      :normalized_name,
      :node,
      :record_exists?,
      :wrapped?,
      :registry_owner,
      :manager,
      :manager_source,
      :resolver_profiles,
      :text_records,
      :warnings
    ]
    defstruct [
      :normalized_name,
      :node,
      :record_exists?,
      :wrapped?,
      :registry_owner,
      :manager,
      :manager_source,
      :resolver_address,
      :ttl,
      :eth_address,
      :contenthash,
      :resolver_profiles,
      :text_records,
      :warnings
    ]

    @type resolver_profiles :: %{
            addr: boolean(),
            text: boolean(),
            contenthash: boolean(),
            extended: boolean()
          }

    @type t :: %__MODULE__{
            normalized_name: String.t(),
            node: String.t(),
            record_exists?: boolean(),
            wrapped?: boolean(),
            registry_owner: String.t(),
            manager: String.t(),
            manager_source: :registry_owner | :name_wrapper_owner,
            resolver_address: String.t() | nil,
            ttl: non_neg_integer(),
            eth_address: String.t() | nil,
            contenthash: String.t() | nil,
            resolver_profiles: resolver_profiles(),
            text_records: %{optional(String.t()) => String.t()},
            warnings: [String.t()]
          }
  end

  @type read_input :: Input.t() | map()

  @spec read_name(read_input()) :: {:ok, NameDetails.t()} | {:error, Error.t()}
  def read_name(%Input{} = input), do: do_read(input)

  def read_name(%{} = params) do
    with {:ok, input} <- build_input(params) do
      do_read(input)
    end
  end

  defp do_read(%Input{} = input) do
    rpc = input.rpc_module || RPC
    network = Networks.get(input.chain_id) || %{}

    ens_registry =
      Validation.normalize_address(input.ens_registry || Map.get(network, :ens_registry))

    name_wrapper =
      Validation.normalize_address(input.name_wrapper || Map.get(network, :name_wrapper))

    with {:ok, registry_address} <- required_address(ens_registry, "ens_registry"),
         {:ok, normalized_name} <- Normalize.normalize(input.ens_name),
         {:ok, node} <- Verify.namehash(normalized_name),
         {:ok, record_exists?} <-
           Contract.record_exists?(rpc, input.rpc_url, registry_address, node),
         {:ok, resolver} <- Contract.fetch_resolver(rpc, input.rpc_url, registry_address, node),
         {:ok, registry_owner} <-
           Contract.fetch_registry_owner(rpc, input.rpc_url, registry_address, node),
         {:ok, ttl} <- Contract.fetch_ttl(rpc, input.rpc_url, registry_address, node),
         {:ok, {manager, manager_source, wrapped?}} <-
           resolve_manager(rpc, input.rpc_url, registry_owner, name_wrapper, node),
         {:ok, resolver_profiles} <- resolver_profiles(rpc, input.rpc_url, resolver),
         {:ok, eth_address} <-
           maybe_fetch_eth_address(
             rpc,
             input.rpc_url,
             resolver,
             node,
             resolver_profiles,
             input.include_address?
           ),
         {:ok, contenthash} <-
           maybe_fetch_contenthash(
             rpc,
             input.rpc_url,
             resolver,
             node,
             resolver_profiles,
             input.include_contenthash?
           ),
         {:ok, text_records} <-
           maybe_fetch_text_records(
             rpc,
             input.rpc_url,
             resolver,
             node,
             resolver_profiles,
             input.text_keys
           ) do
      {:ok,
       %NameDetails{
         normalized_name: normalized_name,
         node: "0x" <> Base.encode16(node, case: :lower),
         record_exists?: record_exists?,
         wrapped?: wrapped?,
         registry_owner: registry_owner,
         manager: manager,
         manager_source: manager_source,
         resolver_address: resolver,
         ttl: ttl,
         eth_address: eth_address,
         contenthash: contenthash,
         resolver_profiles: resolver_profiles,
         text_records: text_records,
         warnings:
           build_warnings(
             normalized_name,
             resolver,
             wrapped?,
             input.text_keys,
             resolver_profiles,
             input.include_contenthash?
           )
       }}
    end
  end

  defp build_input(params) do
    with {:ok, ens_name} <- Validation.required_binary(params, :ens_name),
         {:ok, chain_id} <- Validation.required_integer(params, :chain_id),
         {:ok, rpc_url} <- Validation.required_binary(params, :rpc_url),
         {:ok, text_keys} <- text_keys(params) do
      {:ok,
       %Input{
         ens_name: ens_name,
         chain_id: chain_id,
         rpc_url: rpc_url,
         rpc_module: Map.get(params, :rpc_module),
         ens_registry: Map.get(params, :ens_registry),
         name_wrapper: Map.get(params, :name_wrapper),
         text_keys: text_keys,
         include_address?: truthy(Map.get(params, :include_address?), true),
         include_contenthash?: truthy(Map.get(params, :include_contenthash?), true)
       }}
    end
  end

  defp resolve_manager(_rpc, _rpc_url, registry_owner, nil, _node),
    do: {:ok, {registry_owner, :registry_owner, false}}

  defp resolve_manager(rpc, rpc_url, registry_owner, name_wrapper, node) do
    if registry_owner == name_wrapper do
      with {:ok, wrapped_owner} <- Contract.fetch_wrapped_owner(rpc, rpc_url, name_wrapper, node) do
        {:ok, {wrapped_owner, :name_wrapper_owner, true}}
      end
    else
      {:ok, {registry_owner, :registry_owner, false}}
    end
  end

  defp resolver_profiles(_rpc, _rpc_url, nil) do
    {:ok, %{addr: false, text: false, contenthash: false, extended: false}}
  end

  defp resolver_profiles(rpc, rpc_url, resolver) do
    with {:ok, addr?} <- Contract.supports_addr?(rpc, rpc_url, resolver),
         {:ok, text?} <- Contract.supports_text?(rpc, rpc_url, resolver),
         {:ok, contenthash?} <- Contract.supports_contenthash?(rpc, rpc_url, resolver),
         {:ok, extended?} <- Contract.supports_extended_resolver?(rpc, rpc_url, resolver) do
      {:ok,
       %{
         addr: addr?,
         text: text?,
         contenthash: contenthash?,
         extended: extended?
       }}
    end
  end

  defp maybe_fetch_eth_address(_rpc, _rpc_url, _resolver, _node, _profiles, false), do: {:ok, nil}
  defp maybe_fetch_eth_address(_rpc, _rpc_url, nil, _node, _profiles, true), do: {:ok, nil}

  defp maybe_fetch_eth_address(rpc, rpc_url, resolver, node, %{addr: true}, true) do
    Contract.fetch_addr_record(rpc, rpc_url, resolver, node)
  end

  defp maybe_fetch_eth_address(_rpc, _rpc_url, _resolver, _node, _profiles, true), do: {:ok, nil}

  defp maybe_fetch_contenthash(_rpc, _rpc_url, _resolver, _node, _profiles, false), do: {:ok, nil}
  defp maybe_fetch_contenthash(_rpc, _rpc_url, nil, _node, _profiles, true), do: {:ok, nil}

  defp maybe_fetch_contenthash(rpc, rpc_url, resolver, node, %{contenthash: true}, true) do
    Contract.fetch_contenthash(rpc, rpc_url, resolver, node)
  end

  defp maybe_fetch_contenthash(_rpc, _rpc_url, _resolver, _node, _profiles, true), do: {:ok, nil}

  defp maybe_fetch_text_records(_rpc, _rpc_url, _resolver, _node, _profiles, []), do: {:ok, %{}}
  defp maybe_fetch_text_records(_rpc, _rpc_url, nil, _node, _profiles, _keys), do: {:ok, %{}}

  defp maybe_fetch_text_records(rpc, rpc_url, resolver, node, %{text: true}, keys) do
    Enum.reduce_while(keys, {:ok, %{}}, fn key, {:ok, acc} ->
      case Contract.fetch_text_record(rpc, rpc_url, resolver, node, key) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        {:error, %Error{} = error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp maybe_fetch_text_records(_rpc, _rpc_url, _resolver, _node, _profiles, _keys),
    do: {:ok, %{}}

  defp build_warnings(
         normalized_name,
         resolver,
         wrapped?,
         text_keys,
         resolver_profiles,
         include_contenthash?
       ) do
    []
    |> maybe_add_warning(
      is_nil(resolver),
      exact_node_resolver_warning(normalized_name)
    )
    |> maybe_add_warning(
      wrapped?,
      "ENS name is wrapped, so manager checks use the Name Wrapper owner."
    )
    |> maybe_add_warning(
      text_keys != [] and resolver != nil and not resolver_profiles.text,
      "Resolver does not advertise text-record support for the requested keys."
    )
    |> maybe_add_warning(
      include_contenthash? and resolver != nil and not resolver_profiles.contenthash,
      "Resolver does not advertise content-hash support."
    )
  end

  defp maybe_add_warning(warnings, true, message), do: warnings ++ [message]
  defp maybe_add_warning(warnings, false, _message), do: warnings

  defp exact_node_resolver_warning(name) do
    if likely_subname?(name) do
      "The exact name does not currently have a resolver set. Wildcard or offchain subname resolution is not checked here."
    else
      "ENS name does not currently have a resolver set."
    end
  end

  defp likely_subname?(name) when is_binary(name) do
    name
    |> String.split(".", trim: true)
    |> length()
    |> Kernel.>(2)
  end

  defp required_address(value, _name) when is_binary(value) and value != "",
    do: {:ok, String.downcase(value)}

  defp required_address(_value, name),
    do: {:error, Error.new({:missing_required_input, name})}

  defp text_keys(params) do
    values = Map.get(params, :text_keys) || []

    if is_list(values) and Enum.all?(values, &is_binary/1) do
      {:ok, values}
    else
      {:error, Error.new({:invalid_argument, "text_keys", values})}
    end
  end

  defp truthy(nil, default), do: default
  defp truthy(value, _default) when value in [true, "true", 1, "1"], do: true
  defp truthy(value, _default) when value in [false, "false", 0, "0"], do: false
  defp truthy(_value, default), do: default
end
