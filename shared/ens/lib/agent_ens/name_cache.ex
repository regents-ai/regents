defmodule AgentEns.NameCache do
  @moduledoc """
  Cached verified ENS primary-name resolution for wallet addresses.

  Wraps `AgentEns.PrimaryName.verified_primary_name/2` with a shared cache so
  render paths (chat feeds, profiles) can resolve display names in bulk
  without blocking on JSON-RPC for every wallet.

  The cache backend is injected: `:cache` names the cache and `:cache_module`
  is the module that reads and writes it (`get_json/2` and `put_json/4`), so
  this package carries no cache dependency and apps decide which supervised
  cache to use:

      AgentEns.NameCache.resolve(wallet,
        cache: :ens_names,
        cache_module: MyApp.Cache,
        rpc_url: rpc_url
      )

  Verified names cache for `:positive_ttl` (default 6 hours), wallets without
  a name for `:negative_ttl` (default 15 minutes), and resolver failures for
  `:error_ttl` (default 60 seconds) so a down RPC endpoint is not hammered by
  every render.
  """

  require Logger

  alias AgentEns.Address
  alias AgentEns.PrimaryName

  @default_positive_ttl 6 * 60 * 60
  @default_negative_ttl 15 * 60
  @default_error_ttl 60
  @default_max_concurrency 4
  @default_timeout_ms 10_000

  @typedoc "Options shared by `resolve/2` and `resolve_many/2`."
  @type option ::
          {:cache, atom() | nil}
          | {:cache_module, module()}
          | {:rpc_url, String.t() | nil}
          | {:resolver, (String.t(), keyword() -> {:ok, String.t() | nil} | {:error, term()})}
          | {:positive_ttl, pos_integer()}
          | {:negative_ttl, pos_integer()}
          | {:error_ttl, pos_integer()}
          | {:max_concurrency, pos_integer()}
          | {:timeout_ms, pos_integer()}

  @doc """
  Resolves the verified primary name for one wallet, consulting the cache.

  Returns the name, or `nil` for invalid wallets, wallets without a verified
  name, a blank `:rpc_url`, or resolver failures. Never raises and never
  returns an error tuple — display fallbacks handle `nil`.
  """
  @spec resolve(term(), [option()]) :: String.t() | nil
  def resolve(wallet_address, opts) do
    case Address.normalize(wallet_address) do
      nil -> nil
      wallet -> resolve_normalized(wallet, opts)
    end
  end

  @doc """
  Resolves verified primary names for many wallets concurrently.

  Returns a map of normalized wallet to name-or-`nil`. Invalid wallets are
  dropped. Cache hits are served inline; misses fan out with bounded
  concurrency (`:max_concurrency`, default #{@default_max_concurrency}); a
  resolver call that exceeds `:timeout_ms` yields `nil` for that wallet and
  is not cached.
  """
  @spec resolve_many([term()], [option()]) :: %{optional(String.t()) => String.t() | nil}
  def resolve_many(wallet_addresses, opts) when is_list(wallet_addresses) do
    wallets =
      wallet_addresses
      |> Enum.map(&Address.normalize/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    {hits, misses} =
      Enum.reduce(wallets, {%{}, []}, fn wallet, {hits, misses} ->
        case cached(wallet, opts) do
          {:ok, name} -> {Map.put(hits, wallet, name), misses}
          :miss -> {hits, [wallet | misses]}
        end
      end)

    misses
    |> Task.async_stream(
      fn wallet -> {wallet, resolve_uncached(wallet, opts)} end,
      max_concurrency: Keyword.get(opts, :max_concurrency, @default_max_concurrency),
      timeout: Keyword.get(opts, :timeout_ms, @default_timeout_ms),
      on_timeout: :kill_task,
      zip_input_on_exit: true,
      ordered: false
    )
    |> Enum.reduce(hits, fn
      {:ok, {wallet, name}}, acc -> Map.put(acc, wallet, name)
      {:exit, {wallet, _reason}}, acc -> Map.put(acc, wallet, nil)
    end)
  end

  defp resolve_normalized(wallet, opts) do
    case cached(wallet, opts) do
      {:ok, name} -> name
      :miss -> resolve_uncached(wallet, opts)
    end
  end

  defp cached(wallet, opts) do
    case cache_backend(opts) do
      nil ->
        :miss

      {cache_module, cache} ->
        case cache_module.get_json(cache, cache_key(wallet)) do
          {:ok, %{"name" => name}} when is_binary(name) or is_nil(name) -> {:ok, name}
          {:ok, _other} -> :miss
          :miss -> :miss
          {:error, _reason} -> :miss
        end
    end
  end

  defp resolve_uncached(wallet, opts) do
    rpc_url = Keyword.get(opts, :rpc_url)

    if is_binary(rpc_url) and rpc_url != "" do
      resolver = Keyword.get(opts, :resolver, &PrimaryName.verified_primary_name/2)

      case resolver.(wallet, Keyword.take(opts, [:rpc_url, :ens_registry, :rpc_module])) do
        {:ok, name} when is_binary(name) ->
          write_back(wallet, name, Keyword.get(opts, :positive_ttl, @default_positive_ttl), opts)
          name

        {:ok, nil} ->
          write_back(wallet, nil, Keyword.get(opts, :negative_ttl, @default_negative_ttl), opts)
          nil

        {:error, reason} ->
          Logger.warning("ens name resolution failed: #{inspect(reason)}")
          write_back(wallet, nil, Keyword.get(opts, :error_ttl, @default_error_ttl), opts)
          nil
      end
    else
      nil
    end
  end

  defp write_back(wallet, name, ttl_seconds, opts) do
    case cache_backend(opts) do
      nil ->
        :ok

      {cache_module, cache} ->
        cache_module.put_json(cache, cache_key(wallet), %{"name" => name}, ttl_seconds)
    end
  end

  defp cache_backend(opts) do
    case Keyword.get(opts, :cache) do
      nil -> nil
      cache when is_atom(cache) -> {Keyword.fetch!(opts, :cache_module), cache}
    end
  end

  defp cache_key(wallet), do: "ens:primary-name:" <> wallet
end
