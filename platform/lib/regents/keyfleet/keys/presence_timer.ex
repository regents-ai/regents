defmodule Regents.Keyfleet.Keys.PresenceTimer do
  @moduledoc """
  Every hour (`config :regents, Oban, cron:`): keeps present every Key whose
  shard the site's own timer wallet holds. An owner issues that wallet a shard
  with agent voting off, so it marks presence and nothing else.

  Once any of them has 24 hours or less left, it sends the same `present` step
  a person's Mark present button sends (`Regents.Keyfleet.WalletSteps.KeySteps`), which
  renews them all. It keeps no record of a send: each hour reads the chain again,
  so a send that never landed is sent again.

  Each of these is saved with the site's errors, and again every hour until it
  is fixed (`Regents.Keyfleet.Keys.PresenceTimerError`):

    * a send the node refused or didn't answer;
    * a Key with under 12 hours left, which means twelve runs have not renewed it;
    * under 0.0002 ETH in the wallet, about five days of marking 49 Keys;
    * a shard ending within 30 days, after which the timer can't mark that Key.
  """
  use Oban.Worker, queue: :keyfleet_chain, max_attempts: 1

  alias RegentChain.Abi
  alias RegentChain.Transaction
  alias Regents.Keyfleet.Chain.JsonRpc
  alias Regents.Keyfleet.Chain.RpcClient
  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.Keys.PresenceTimerError
  alias Regents.Keyfleet.WalletSteps.Build

  require Logger

  @mark_within 24 * 3600
  @warn_within 12 * 3600
  @shard_warning 30 * 86_400
  @low_eth 200_000_000_000_000

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case private_key!() do
      :disabled ->
        :ok

      key ->
        {:ok, wallet} = Transaction.address(key)
        shards = Keys.active_shards_held_by!(wallet)

        if shards != [], do: warn_low_eth(wallet)

        for {fleet_id, held} <- Enum.group_by(shards, & &1.fleet_id) do
          keep_present(fleet_id, held, wallet, key)
        end

        :ok
    end
  end

  # The raised words never carry the setting's value. Unset (nil or empty) means
  # no timer wallet is configured in this environment.
  defp private_key! do
    case Application.get_env(:regents, __MODULE__, [])[:key] do
      nil ->
        :disabled

      "" ->
        :disabled

      "0x" <> hex ->
        case Base.decode16(hex, case: :mixed) do
          {:ok, <<key::binary-size(32)>>} -> key
          _malformed -> raise "KEYFLEET_PRESENCE_TIMER_KEY is not 0x and 64 hex digits"
        end

      _malformed ->
        raise "KEYFLEET_PRESENCE_TIMER_KEY is not 0x and 64 hex digits"
    end
  end

  defp keep_present(fleet_id, shards, wallet, key) do
    {:ok, %{fleet: fleet, chain: chain}, built} =
      Build.build(%{fleet_id: fleet_id, flow: :present}, wallet)

    warn_shards_ending(fleet, shards)

    case built do
      %{problem: nil, figures: figures, steps: steps} ->
        left = seconds_left(figures)
        warn_lapsing(fleet, left)
        if due?(left, figures), do: mark(fleet, chain, steps, wallet, key)

      %{problem: problem} ->
        Logger.warning("Presence timer read nothing for #{fleet.name}: #{problem}")
    end
  end

  # Only the Keys old enough to mark: a newer one has no presence to renew yet.
  defp seconds_left(%{keys: keys, ready: ready}) do
    now = DateTime.utc_now()

    for %{token_id: token_id, until: until} <- keys, token_id in ready do
      {token_id, if(until, do: DateTime.diff(until, now), else: 0)}
    end
  end

  defp due?(left, %{blocked: blocked}),
    do: not is_map_key(blocked, "present") and Enum.any?(left, &(elem(&1, 1) <= @mark_within))

  defp mark(fleet, chain, steps, wallet, key) do
    step = Enum.find(steps, &(&1.step == "present"))

    case send_step(step, chain.chain_id, wallet, key) do
      {:ok, hash} ->
        Logger.info("Presence timer marked #{fleet.name}: #{hash}")

      {:error, why} ->
        PresenceTimerError.report("The presence timer's send for #{fleet.name} failed: #{why}.")
        :ok
    end
  end

  # The nonce is read at the latest block: this wallet is the only sender, and a
  # send still waiting from an hour ago is replaced by this one.
  defp send_step(step, chain_id, wallet, key) do
    with {:ok, nonce} <- quantity("eth_getTransactionCount", [wallet, "latest"]),
         {:ok, gas} <-
           quantity("eth_estimateGas", [%{from: wallet, to: step.to, data: step.data}, "latest"]),
         {:ok, tip} <- quantity("eth_maxPriorityFeePerGas", []),
         {:ok, %{base_fee: base_fee}} <- head() do
      {:ok, %{raw: raw, hash: hash}} =
        Transaction.sign(
          %{
            chain_id: chain_id,
            nonce: nonce,
            max_priority_fee_per_gas: tip,
            max_fee_per_gas: 2 * base_fee + tip,
            gas: div(gas * 12, 10),
            to: step.to,
            value: 0,
            data: step.data
          },
          key
        )

      with {:ok, _hash} <- request("eth_sendRawTransaction", [raw]), do: {:ok, hash}
    end
  end

  defp head do
    case RpcClient.head() do
      {:ok, head} -> {:ok, head}
      {:error, _reason} -> {:error, "the node didn't answer for its latest block"}
    end
  end

  defp quantity(method, params) do
    with {:ok, answer} <- request(method, params),
         {:ok, number} <- Abi.quantity(answer) do
      {:ok, number}
    else
      :error -> {:error, "#{method} answered something unreadable"}
      {:error, why} -> {:error, why}
    end
  end

  # The node's own words when it refuses; never its address.
  defp request(method, params) do
    case JsonRpc.request(method, params) do
      {:ok, answer} -> {:ok, answer}
      {:error, {:rpc_error, %{message: message}}} -> {:error, "#{method}: #{message}"}
      {:error, {:unavailable, _detail}} -> {:error, "the node didn't answer #{method}"}
    end
  end

  defp warn_low_eth(wallet) do
    with {:ok, wei} <- quantity("eth_getBalance", [wallet, "latest"]),
         true <- wei < @low_eth do
      PresenceTimerError.report(
        "The presence timer's wallet #{wallet} is low on ETH: #{wei} wei left. " <>
          "Send it about 0.005 ETH on Base."
      )

      :ok
    end
  end

  defp warn_lapsing(fleet, left) do
    with [_ | _] = lapsing <- for({key, seconds} <- left, seconds < @warn_within, do: key) do
      PresenceTimerError.report(
        "Keys of #{fleet.name} have under 12 hours of presence left: #{Enum.join(lapsing, ", ")}. " <>
          "Their owners can press Mark present on the Key's page."
      )

      :ok
    end
  end

  defp warn_shards_ending(fleet, shards) do
    now = DateTime.utc_now()

    with [_ | _] = ending <-
           for(
             shard <- shards,
             DateTime.diff(shard.expires_at, now) < @shard_warning,
             do: shard.token_id
           ) do
      PresenceTimerError.report(
        "The presence timer's shards of #{fleet.name} end within 30 days: " <>
          "#{Enum.join(ending, ", ")}. Their owners can issue them again on the Key's page."
      )

      :ok
    end
  end
end
