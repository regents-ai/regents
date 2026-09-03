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
  """

  alias AgentEns.Internal.Contract
  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System, as: SystemActor

  @supervisor __MODULE__.TaskSupervisor
  @ethereum_chain_id 1
  @ens_registry "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e"
  @avatar_record "avatar"
  @unnamed %{ens_name: nil, ens_avatar_url: nil}

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
    do: Accounts.put_ens_identity(account_id, name, avatar, actor: %SystemActor{})

  defp store(_account_id, :unavailable), do: :ok

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
    do: %{ens_name: name, ens_avatar_url: image_url(records[@avatar_record])}

  defp owned(_someone_elses_name, _wallet), do: @unnamed

  # The avatar record is free text. An `https://` image goes straight into the
  # page; an `ipfs://` URI would need a gateway this product has not chosen, and
  # an `eip155:` NFT reference would need a second chain read and a metadata
  # fetch. Neither is supported, and neither is shown as a broken image: the
  # wallet's own generated picture stands for every wallet without an https one.
  defp image_url("https://" <> _image = url), do: url
  defp image_url(_unsupported), do: nil

  defp rpc, do: Application.fetch_env!(:ash_platform, :ethereum_rpc_module)

  defp deadline_ms, do: Application.fetch_env!(:ash_platform, :ens_lookup_deadline_ms)

  defp announce(account_id),
    do:
      Phoenix.PubSub.broadcast(
        AshPlatform.PubSub,
        topic(account_id),
        {:ens_lookup_finished, account_id}
      )
end
