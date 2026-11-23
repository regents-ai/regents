defmodule Regents.Keyfleet.WalletSteps.LaunchSteps do
  @moduledoc """
  The upkeep of a fleet's token launch through Autolaunch, which anyone may
  press once the sale has ended: settling the sale, adding the launched token
  to the daily split, releasing the launch's tokens set aside for the
  treasury, and collecting the pool's fees. `Regents.Keyfleet.WalletSteps.Build`
  describes what every builder answers.

  The launch is the one the treasury has added to the daily split, or before
  that, the latest launch a carried-out proposal made: the one its
  transaction's receipt names, made by and for the fleet's own treasury.
  """

  alias RegentChain.{Call, Event, Review}
  alias Regents.Chain.Client, as: ChainClient
  alias Regents.Keyfleet.Proposals
  alias Regents.Keyfleet.Proposals.Actions
  alias Regents.Keyfleet.WalletSteps.Reads

  @launch_created "LaunchCreated(uint256,address,address,address,address,address,uint64,uint64)"
  # The strategy's `Lifecycle`, in its order.
  @lifecycles [:none, :active, :graduated, :failed]

  @doc false
  def steps(:launch_upkeep, %{fleet: fleet, chain: chain}) do
    figures = %{launch_id: nil}

    with {:ok, reads} <- reads(figures),
         {:ok, bound_id} <- uint(reads, fleet.treasury_address, "launchId()", figures),
         {:ok, launch_id} <- launch_id(bound_id, fleet, chain, figures),
         {:ok, launch} <- launch(reads, fleet, launch_id, figures) do
      {:ok, steps(fleet, launch_id, launch),
       %{
         launch_id: launch_id,
         token: launch.subject,
         lifecycle: launch.lifecycle,
         bound?: bound_id != 0,
         blocked: blocked(launch, bound_id != 0, Reads.block(reads))
       }}
    end
  end

  defp steps(fleet, launch_id, launch) do
    [
      Review.step("settle", launch.strategy, Call.encode("migrate(address)", [launch.auction])),
      Review.step(
        "bind",
        fleet.treasury_address,
        Call.encode("bindLaunchToken(uint256)", [launch_id])
      ),
      Review.step("release", launch.escrow, Call.encode("release()", [])),
      Review.step("collect", launch.locker, Call.encode("collect(uint256)", [launch.lp_token_id]))
    ]
  end

  # Each button the launch's own state makes certain to fail, with why.
  defp blocked(launch, bound?, block) do
    %{
      "settle" => settle_blocked(launch, block),
      "bind" => if(bound?, do: :bound, else: sold_blocked(launch)),
      "release" => sold_blocked(launch),
      "collect" => sold_blocked(launch)
    }
    |> Enum.reject(fn {_step, reason} -> is_nil(reason) end)
    |> Map.new()
  end

  defp settle_blocked(%{lifecycle: :active, migration_block: at}, block) when block < at,
    do: :sale_running

  defp settle_blocked(%{lifecycle: :active}, _block), do: nil
  defp settle_blocked(_launch, _block), do: :launch_settled

  defp sold_blocked(%{lifecycle: :graduated}), do: nil
  defp sold_blocked(%{lifecycle: :failed}), do: :launch_failed
  defp sold_blocked(_launch), do: :not_sold

  defp launch_id(0, fleet, chain, figures) do
    fleet.id
    |> Proposals.executed()
    |> Enum.filter(fn proposal -> Enum.any?(proposal.calls, &launch?(&1, fleet)) end)
    |> case do
      [] -> {:problem, :no_launch, figures}
      [latest | _earlier] -> launched(latest.execution.transaction_hash, fleet, chain, figures)
    end
  end

  defp launch_id(bound_id, _fleet, _chain, _figures), do: {:ok, bound_id}

  defp launch?(call, fleet), do: match?({:launch, _launch}, Actions.decode(call, fleet))

  # The launch a carried-out proposal's transaction made, from its receipt.
  defp launched(hash, fleet, chain, figures) do
    treasury = fleet.treasury_address

    with {:ok, %{"logs" => logs}} <- ChainClient.receipt(chain, hash),
         {:ok, {[launch_id, launcher, _subject], _data}} <-
           Event.one(logs, @launch_created, fleet.autolaunch_factory_address, 3, 5),
         {:ok, ^treasury} <- Event.address(launcher) do
      {:ok, launch_id}
    else
      _unread -> {:problem, :unread, figures}
    end
  end

  # The launch as the factory recorded it, and as its strategy says it
  # stands now.
  defp launch(reads, fleet, launch_id, figures) do
    factory = fleet.autolaunch_factory_address

    with {:ok, [_launcher, subject, auction, escrow, _treasury]} <-
           Reads.many(
             reads,
             factory,
             "launches(uint256)",
             [launch_id],
             List.duplicate(:address, 5)
           ),
         {:ok, strategy} <- Reads.one(reads, factory, "strategy()", [], :address),
         {:ok, locker} <- Reads.one(reads, strategy, "lpLocker()", [], :address),
         {:ok, distribution} <-
           Reads.many(reads, strategy, "distribution(address)", [auction], distribution_types()) do
      [lifecycle, _start, _end, _claim, migration_block | _rest] = distribution

      {:ok,
       %{
         subject: subject,
         auction: auction,
         escrow: escrow,
         strategy: strategy,
         locker: locker,
         lifecycle: Enum.at(@lifecycles, lifecycle),
         migration_block: migration_block,
         lp_token_id: List.last(distribution)
       }}
    else
      _unread -> {:problem, :unread, figures}
    end
  end

  defp distribution_types do
    [{:uint, 8}] ++
      List.duplicate({:uint, 64}, 4) ++
      List.duplicate({:uint, 128}, 3) ++
      [{:uint, 160}, {:uint, 256}] ++ List.duplicate(:address, 5) ++ [:bytes32, {:uint, 256}]
  end

  defp reads(figures) do
    case Reads.at_head() do
      {:ok, reads} -> {:ok, reads}
      {:error, _reason} -> {:problem, :unread, figures}
    end
  end

  defp uint(reads, to, signature, figures) do
    case Reads.one(reads, to, signature, [], {:uint, 256}) do
      {:ok, value} -> {:ok, value}
      {:error, _reason} -> {:problem, :unread, figures}
    end
  end
end
