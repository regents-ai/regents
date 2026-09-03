defmodule AshPlatform.Ens do
  @moduledoc """
  Reads the ENS name and avatar Ethereum mainnet publishes for a signed wallet.

  Sign-in never waits for this. `refresh/1` hands the lookup to a supervised task
  and returns immediately, the lookup gives up at a fixed deadline, and a lookup
  that fails or expires writes nothing, so the last known name and picture stand.
  A finished attempt announces itself on `topic/1` and the pages showing that
  account read it again.

  A wallet's reverse record only claims a name. The name is resolved forward
  again and kept only when it resolves back to the same wallet, so no one can
  wear a name they do not own.

  A name's picture is kept only when its address really answers with one, so a
  wallet is drawn with its own generated picture rather than with a box the
  browser cannot fill.
  """

  alias AgentEns.Internal.Contract
  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System, as: SystemActor

  @supervisor __MODULE__.TaskSupervisor
  @ethereum_chain_id 1
  @ens_registry "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e"
  @avatar_record "avatar"
  @unnamed %{ens_name: nil, ens_avatar_url: nil}

  # ENS publishes an address that resolves any name's avatar record — an image
  # address, an `ipfs://` URI, or a reference to the NFT holding the picture —
  # and answers with the image itself.
  @avatar_service "https://metadata.ens.domains/mainnet/avatar/"

  @doc false
  def child_spec(_options),
    do: Supervisor.child_spec({Task.Supervisor, name: @supervisor}, id: @supervisor)

  @doc "The topic a finished lookup for `account_id` is announced on."
  @spec topic(integer()) :: String.t()
  def topic(account_id) when is_integer(account_id), do: "account_ens_identity:#{account_id}"

  @doc """
  Starts the mainnet lookup for a signed-in account's wallet.

  Returns as soon as the task is started, whatever the chain does next.
  """
  @spec refresh(map()) :: :ok
  def refresh(%{id: account_id, wallet_address: wallet})
      when is_integer(account_id) and is_binary(wallet),
      do: start(account_id, wallet, Application.get_env(:ash_platform, :ethereum_read_rpc_url))

  defp start(_account_id, _wallet, nil), do: :ok

  defp start(account_id, wallet, endpoint) do
    Task.Supervisor.start_child(@supervisor, fn ->
      store(account_id, bounded_lookup(String.downcase(wallet), endpoint))
      announce(account_id)
    end)

    :ok
  end

  defp store(account_id, {:ok, %{ens_name: name, ens_avatar_url: avatar}}),
    do: Accounts.put_ens_identity(account_id, name, served(avatar), actor: %SystemActor{})

  defp store(_account_id, :unavailable), do: :ok

  # A picture is kept only when its address really answers with one, asked once
  # on its own budget. So a record the ENS service cannot resolve, an image that
  # has since gone, and a host that will not answer all leave the wallet's
  # generated picture standing rather than a box the browser cannot fill — and
  # none of them costs the name, which was read before this is asked.
  defp served(nil), do: nil

  defp served(url) do
    case avatar_client().head(url, receive_timeout: avatar_deadline_ms(), retry: false) do
      {:ok, %{status: 200}} -> url
      _unserved -> nil
    end
  end

  # The chain calls run in their own task so the deadline is wall-clock, not the
  # sum of however many round trips a resolver happens to need.
  defp bounded_lookup(wallet, endpoint) do
    task = Task.Supervisor.async_nolink(@supervisor, fn -> lookup(wallet, endpoint) end)

    case Task.yield(task, deadline_ms()) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, resolved}} -> {:ok, resolved}
      _expired_or_failed -> :unavailable
    end
  end

  defp lookup(wallet, endpoint) do
    with {:ok, node} <- AgentEns.Verify.namehash(reverse_name(wallet)),
         {:ok, resolver} <- Contract.fetch_resolver(rpc(), endpoint, @ens_registry, node),
         {:ok, claimed} <- Contract.fetch_name_record(rpc(), endpoint, resolver, node) do
      forward_resolved(String.trim(claimed), wallet, endpoint)
    end
  end

  defp reverse_name("0x" <> address), do: address <> ".addr.reverse"

  defp forward_resolved("", _wallet, _endpoint), do: {:ok, @unnamed}

  defp forward_resolved(claimed, wallet, endpoint) do
    with {:ok, details} <- read_name(claimed, endpoint), do: {:ok, owned(details, wallet)}
  end

  defp read_name(name, endpoint) do
    AgentEns.read_name(%{
      ens_name: name,
      chain_id: @ethereum_chain_id,
      rpc_url: endpoint,
      rpc_module: rpc(),
      text_keys: [@avatar_record],
      include_contenthash?: false
    })
  end

  defp owned(%{eth_address: wallet, normalized_name: name, text_records: records}, wallet),
    do: %{ens_name: name, ens_avatar_url: image_url(records[@avatar_record], name)}

  defp owned(_someone_elses_name, _wallet), do: @unnamed

  # The avatar record is free text, and only an image address is something a
  # browser can load. Every other kind the record may hold is read through the
  # ENS service, which resolves the record itself, so a name is drawn with its
  # own picture however that picture is published. A name that publishes nothing
  # is drawn with the wallet's generated picture.
  defp image_url(record, name) when is_binary(record) do
    case String.trim(record) do
      "" -> nil
      "https://" <> _image = url -> url
      _other_kind -> @avatar_service <> URI.encode(name, &URI.char_unreserved?/1)
    end
  end

  defp image_url(_absent, _name), do: nil

  defp rpc, do: Application.fetch_env!(:ash_platform, :ethereum_rpc_module)

  defp deadline_ms, do: Application.fetch_env!(:ash_platform, :ens_lookup_deadline_ms)

  defp avatar_client, do: Application.fetch_env!(:ash_platform, :ens_avatar_http_client)

  defp avatar_deadline_ms,
    do: Application.fetch_env!(:ash_platform, :ens_avatar_deadline_ms)

  defp announce(account_id),
    do:
      Phoenix.PubSub.broadcast(
        AshPlatform.PubSub,
        topic(account_id),
        {:ens_lookup_finished, account_id}
      )
end
