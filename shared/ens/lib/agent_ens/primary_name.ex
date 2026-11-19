defmodule AgentEns.PrimaryName do
  @moduledoc """
  Verified ENS primary-name (reverse record) resolution on Ethereum mainnet.

  Looks up the reverse record for a wallet, then forward-resolves the claimed
  name and only returns it when the name resolves back to the same wallet.
  Wallets without a verified primary name yield `{:ok, nil}`.

  `verified_primary_identity/2` adds the name's avatar, read only through the
  ENS avatar service.
  """

  alias AgentEns.Address
  alias AgentEns.Internal.AvatarHTTP
  alias AgentEns.Internal.Contract
  alias AgentEns.Internal.RPC
  alias AgentEns.Internal.Validation
  alias AgentEns.Verify

  @ethereum_chain_id 1
  @default_ens_registry "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e"
  @avatar_record "avatar"
  # A name the service has not been asked about for an hour takes it one to
  # five seconds to answer, picture or none.
  @avatar_timeout_ms 10_000

  # ENS resolves any name's avatar record (an image address, an `ipfs://` URI or
  # a reference to the NFT holding the picture) and answers with the image
  # itself, so a picture is only ever read from this one host, never from an
  # address a record names.
  @avatar_service "https://metadata.ens.domains/mainnet/avatar/"

  @doc """
  Resolves the verified primary name for `wallet_address`.

  Options:

    * `:rpc_url` — Ethereum mainnet JSON-RPC URL (required; a blank or
      missing value returns `{:error, %AgentEns.Error{}}`)
    * `:ens_registry` — ENS registry address (defaults to the canonical
      mainnet registry)
    * `:rpc_module` — RPC module used for `eth_call` (defaults to
      `AgentEns.Internal.RPC`)
  """
  @spec verified_primary_name(String.t() | nil, keyword()) ::
          {:ok, String.t() | nil} | {:error, term()}
  def verified_primary_name(wallet_address, opts \\ []) do
    with {:ok, %{normalized_name: name}} <- verified(wallet_address, opts, []), do: {:ok, name}
  end

  @doc """
  The verified primary name for `wallet_address` and its avatar, or `{:ok, nil}`
  when the wallet has no verified primary name.

  `avatar_url` is the ENS avatar service's address for the name, given only when
  the name publishes an avatar record and the service answers with a picture;
  otherwise it is `nil`. Nothing is fetched from an address the record names.

  The service says there is no picture with a 404 (a name without one), a 400
  (a name it refuses) or a redirect, which is never followed. A service that
  does not answer in time, or gives any other answer (busy, broken, or refusing
  this caller), is `{:error, reason}`, like a chain read that fails: it says
  nothing about the picture, so the caller keeps what it holds and asks again.

  Takes the options of `verified_primary_name/2`, and:

    * `:avatar_timeout_ms` — how long the avatar service may take to answer
      (defaults to 10000)
    * `:http_client` — module whose `head(url, options)` asks the avatar service
      (defaults to `AgentEns.Internal.AvatarHTTP`, through Req)
  """
  @spec verified_primary_identity(String.t() | nil, keyword()) ::
          {:ok, %{name: String.t(), avatar_url: String.t() | nil} | nil} | {:error, term()}
  def verified_primary_identity(wallet_address, opts \\ []) do
    with {:ok, %{normalized_name: name, text_records: records}} <-
           verified(wallet_address, opts, [@avatar_record]),
         {:ok, avatar_url} <- avatar_url(name, records[@avatar_record], opts) do
      {:ok, %{name: name, avatar_url: avatar_url}}
    end
  end

  defp verified(wallet_address, opts, text_keys) do
    ens_registry = Keyword.get(opts, :ens_registry, @default_ens_registry)
    rpc_module = Keyword.get(opts, :rpc_module, RPC)

    with {:ok, rpc_url} <- Validation.required_binary(Map.new(opts), :rpc_url),
         wallet when is_binary(wallet) <- Address.normalize(wallet_address),
         {:ok, reverse_name} <- reverse_name(wallet, rpc_url, ens_registry, rpc_module),
         true <- reverse_name != "",
         {:ok, %{eth_address: ^wallet} = details} <-
           AgentEns.read_name(%{
             ens_name: reverse_name,
             chain_id: @ethereum_chain_id,
             rpc_url: rpc_url,
             rpc_module: rpc_module,
             text_keys: text_keys,
             include_contenthash?: false
           }) do
      {:ok, details}
    else
      nil -> {:ok, nil}
      false -> {:ok, nil}
      {:ok, %{eth_address: _other}} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
      _other -> {:ok, nil}
    end
  end

  defp avatar_url(name, record, opts) when is_binary(record) do
    if String.trim(record) == "",
      do: {:ok, nil},
      else: served(@avatar_service <> URI.encode(name, &URI.char_unreserved?/1), opts)
  end

  defp avatar_url(_name, _absent, _opts), do: {:ok, nil}

  defp served(url, opts) do
    client = Keyword.get(opts, :http_client, AvatarHTTP)
    timeout = Keyword.get(opts, :avatar_timeout_ms, @avatar_timeout_ms)

    case client.head(url, receive_timeout: timeout, retry: false, redirect: false) do
      {:ok, %{status: 200}} ->
        {:ok, url}

      # The service's own answers about the name: none (404), a name it
      # refuses (400), or a redirect, which is never followed.
      {:ok, %{status: status}} when status in [400, 404] or status in 300..399 ->
        {:ok, nil}

      # Busy, broken or refusing this caller says nothing about the picture,
      # the same as no answer.
      {:ok, %{status: status}} ->
        {:error, {:avatar_service_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp reverse_name(wallet, rpc_url, ens_registry, rpc_module) do
    with {:ok, node} <- reverse_node(wallet),
         {:ok, resolver} <- Contract.fetch_resolver(rpc_module, rpc_url, ens_registry, node),
         {:ok, name} <- Contract.fetch_name_record(rpc_module, rpc_url, resolver, node) do
      {:ok, String.trim(name)}
    end
  end

  defp reverse_node("0x" <> address), do: Verify.namehash("#{address}.addr.reverse")
end
