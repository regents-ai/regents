defmodule AshPlatform.Autolaunch.LabMarketFeed do
  @moduledoc false

  use GenServer

  @topic "autolaunch:lab_market"
  @capacity 256
  @initial_delay 1_000
  @max_delay 10_000

  def topic, do: @topic

  def start_link(options \\ []) do
    case Keyword.get(options, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, options)
      name -> GenServer.start_link(__MODULE__, options, name: name)
    end
  end

  def snapshot(server \\ __MODULE__) do
    GenServer.call(server, :snapshot)
  end

  def refresh(server \\ __MODULE__) do
    send(server, :poll)
    :ok
  end

  @impl true
  def init(options) do
    state = %{
      reader: Keyword.get(options, :reader, Reader),
      projector: Keyword.get(options, :projector, Projector),
      pubsub: Keyword.get(options, :pubsub, AshPlatform.PubSub),
      poll?: Keyword.get(options, :poll?, true),
      delay: Keyword.get(options, :initial_delay, @initial_delay),
      generation: 0,
      binding: nil,
      accepted_head: nil,
      failed_head: nil,
      snapshots: %{},
      degraded?: false,
      in_flight: nil,
      timer: nil
    }

    {:ok, if(state.poll?, do: schedule(state, 0), else: state)}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply,
     %{
       generation: state.generation,
       head: state.accepted_head,
       degraded?: state.degraded?,
       auctions: state.snapshots
     }, state}
  end

  @impl true
  def handle_info(:poll, %{in_flight: nil} = state) do
    token = make_ref()
    parent = self()
    reader = state.reader

    Task.start(fn -> send(parent, {:head, token, safely(fn -> reader.head() end)}) end)

    {:noreply, %{state | in_flight: %{token: token, stage: :head}, timer: nil}}
  end

  def handle_info(:poll, state), do: {:noreply, state}

  def handle_info({:head, token, result}, %{in_flight: %{token: token, stage: :head}} = state) do
    case result do
      {:ok, head} -> handle_head(state, head)
      {:error, _reason} -> {:noreply, failed(state)}
    end
  end

  def handle_info({:head, _token, _result}, state), do: {:noreply, state}

  def handle_info(
        {:snapshots, token, result},
        %{in_flight: %{token: token, stage: :snapshots, head: head}} = state
      ) do
    case result do
      {:ok, snapshots} -> finish_refresh(state, head, snapshots)
      {:error, _reason} -> {:noreply, failed_exact_head(state, head)}
    end
  end

  def handle_info({:snapshots, _token, _result}, state), do: {:noreply, state}

  defp handle_head(state, head) do
    cond do
      state.binding && state.binding != head.binding ->
        state
        |> invalidate_for(head.binding)
        |> begin_snapshots(head)

      failed_for_head?(state, head) ->
        {:noreply, succeeded(%{state | in_flight: nil})}

      same_head?(state.accepted_head, head.block) ->
        {:noreply, succeeded(%{state | in_flight: nil, degraded?: false})}

      moved_sideways?(state.accepted_head, head.block) or
          moved_backwards?(state.accepted_head, head.block) ->
        {:noreply,
         succeeded(%{
           state
           | in_flight: nil,
             degraded?: true,
             failed_head: nil,
             generation: state.generation + 1
         })}

      true ->
        begin_snapshots(%{state | binding: head.binding}, head)
    end
  end

  defp begin_snapshots(state, head) do
    token = make_ref()
    parent = self()
    reader = state.reader

    Task.start(fn ->
      send(parent, {:snapshots, token, safely(fn -> reader.snapshots(head, @capacity) end)})
    end)

    {:noreply,
     %{
       state
       | in_flight: %{token: token, stage: :snapshots, head: head},
         timer: nil
     }}
  end

  defp finish_refresh(state, head, snapshots) do
    with {:ok, current_binding} <- state.reader.current_binding(),
         true <- current_binding == head.binding,
         {:ok, durable_changed_ids} <- state.projector.project(snapshots, head),
         {:ok, publish_binding} <- state.reader.current_binding(),
         true <- publish_binding == head.binding do
      snapshots = Map.new(snapshots, &{&1.auction_address, &1})

      cache_changed_ids = changed_snapshot_ids(state.snapshots, snapshots)
      changed_ids = Enum.uniq(durable_changed_ids ++ cache_changed_ids)
      generation = state.generation + 1

      if changed_ids != [] do
        Phoenix.PubSub.broadcast(
          state.pubsub,
          @topic,
          {:autolaunch_market_updated,
           %{
             generation: generation,
             auction_ids: changed_ids,
             block_number: head.block.number,
             block_hash: head.block.hash
           }}
        )
      end

      {:noreply,
       succeeded(%{
         state
         | generation: generation,
           binding: head.binding,
           accepted_head: head.block,
           failed_head: nil,
           snapshots: snapshots,
           degraded?: false,
           in_flight: nil
       })}
    else
      false -> {:noreply, failed(%{state | in_flight: nil})}
      {:error, _reason} -> {:noreply, failed_exact_head(state, head)}
    end
  end

  defp invalidate_for(state, binding) do
    %{
      state
      | generation: state.generation + 1,
        binding: binding,
        accepted_head: nil,
        failed_head: nil,
        snapshots: %{},
        degraded?: false,
        in_flight: nil
    }
  end

  defp failed_exact_head(state, head) do
    failed(%{
      state
      | failed_head: %{binding: head.binding, block: head.block},
        in_flight: nil
    })
  end

  defp failed_for_head?(
         %{failed_head: %{binding: binding, block: block}},
         %{binding: binding, block: block}
       ),
       do: true

  defp failed_for_head?(_state, _head), do: false

  defp same_head?(%{number: number, hash: hash}, %{number: number, hash: hash}), do: true
  defp same_head?(_accepted, _observed), do: false

  defp moved_sideways?(%{number: number, hash: old}, %{number: number, hash: new}),
    do: old != new

  defp moved_sideways?(_accepted, _observed), do: false

  defp moved_backwards?(%{number: accepted}, %{number: observed}), do: observed < accepted
  defp moved_backwards?(_accepted, _observed), do: false

  defp changed_snapshot_ids(previous, current) do
    current
    |> Enum.reduce([], fn {address, snapshot}, changed ->
      if Map.get(previous, address) == snapshot,
        do: changed,
        else: [snapshot.auction_id | changed]
    end)
    |> Enum.reverse()
  end

  defp succeeded(state) do
    state
    |> Map.put(:delay, @initial_delay)
    |> schedule(@initial_delay)
  end

  defp failed(state) do
    delay = min(max(state.delay * 2, 2_000), @max_delay)
    state |> Map.put(:delay, delay) |> schedule(delay)
  end

  defp schedule(%{poll?: false} = state, _delay), do: state

  defp schedule(state, delay) do
    if state.timer, do: Process.cancel_timer(state.timer)
    %{state | timer: Process.send_after(self(), :poll, delay)}
  end

  defp safely(callback) do
    callback.()
  rescue
    _error -> {:error, :market_feed_unavailable}
  catch
    _kind, _reason -> {:error, :market_feed_unavailable}
  end

  defmodule Reader do
    @moduledoc false

    @read_concurrency 8
    @read_timeout 10_000

    alias AshPlatform.Actors.System, as: SystemActor
    alias AshPlatform.Autolaunch
    alias AshPlatform.Autolaunch.{Lab, LabRpc}
    alias AshPlatform.WalletActions.Rpc

    def head do
      with {:ok, config, block, opts} <- LabRpc.current([:strategy]) do
        {:ok, %{config: config, binding: Lab.full_binding(config), block: block, rpc_opts: opts}}
      end
    end

    def current_binding do
      case Lab.current() do
        {:ok, config} -> {:ok, Lab.full_binding(config)}
        {:error, reason} -> {:error, reason}
      end
    end

    def snapshots(head, capacity) do
      with {:ok, auctions} <- Autolaunch.list_lab_market_auctions(actor: %SystemActor{}),
           true <- length(auctions) <= capacity do
        collect_snapshots(auctions, head)
      else
        false -> {:error, :market_capacity_exceeded}
        {:error, reason} -> {:error, reason}
      end
    end

    defp collect_snapshots(auctions, head) do
      auctions
      |> Task.async_stream(&snapshot(head, &1),
        max_concurrency: @read_concurrency,
        ordered: false,
        timeout: @read_timeout,
        on_timeout: :kill_task
      )
      |> Enum.reduce_while({:ok, []}, fn result, {:ok, snapshots} ->
        collect_snapshot(result, snapshots)
      end)
      |> reverse_snapshots()
    end

    defp collect_snapshot({:ok, {:ok, snapshot}}, snapshots),
      do: {:cont, {:ok, [snapshot | snapshots]}}

    defp collect_snapshot({:ok, {:error, reason}}, _snapshots),
      do: {:halt, {:error, reason}}

    defp collect_snapshot({:exit, _reason}, _snapshots),
      do: {:halt, {:error, :market_snapshot_failed}}

    defp reverse_snapshots({:ok, snapshots}), do: {:ok, Enum.reverse(snapshots)}
    defp reverse_snapshots(error), do: error

    defp snapshot(%{config: config, block: block, rpc_opts: opts}, auction) do
      address = auction.auction_address

      with :ok <- LabRpc.ensure_contract(address, block, opts),
           {:ok, start_block} <- call_uint(config, address, "startBlock()", block, opts),
           {:ok, end_block} <- call_uint(config, address, "endBlock()", block, opts),
           {:ok, claim_block} <- call_uint(config, address, "claimBlock()", block, opts),
           {:ok, graduated?} <- call_bool(config, address, "isGraduated()", block, opts),
           {:ok, clearing_price} <- call_uint(config, address, "clearingPrice()", block, opts),
           {:ok, currency_raised} <- call_uint(config, address, "currencyRaised()", block, opts),
           {:ok, remaining_supply} <- call_uint(config, address, "remainingSupply()", block, opts),
           {:ok, distribution} <-
             LabRpc.words(
               config,
               :strategy,
               "distribution(address)",
               [address],
               18,
               block,
               opts
             ) do
        lifecycle = Enum.at(distribution, 0)

        {:ok,
         %{
           auction_id: auction.id,
           auction_address: String.downcase(address),
           state: market_state(auction.state, lifecycle, graduated?, block.number, start_block),
           current_clearing_price: Rpc.format_units(clearing_price, 18),
           block_number: block.number,
           block_hash: block.hash,
           start_block: start_block,
           end_block: end_block,
           claim_block: claim_block,
           currency_raised: Rpc.format_units(currency_raised, 18),
           remaining_supply: Rpc.format_units(remaining_supply, 18),
           graduated?: graduated?,
           pool_id: pool_id(Enum.at(distribution, 16))
         }}
      end
    end

    defp call_uint(config, address, signature, block, opts),
      do: LabRpc.call_uint(config, address, "auction", signature, [], block, opts)

    defp call_bool(config, address, signature, block, opts) do
      AshPlatform.WalletActions.Rpc.call_bool(
        address,
        AshPlatform.Autolaunch.LabAbi.encode(config.abis["auction"], signature, []),
        block,
        opts
      )
    end

    defp market_state(_current, 2, _graduated?, _block, _start), do: :graduated
    defp market_state(_current, 3, _graduated?, _block, _start), do: :failed
    defp market_state(_current, _lifecycle, true, _block, _start), do: :graduated
    defp market_state(:active, _lifecycle, _graduated?, _block, _start), do: :active

    defp market_state(_current, _lifecycle, _graduated?, block, start) when block >= start,
      do: :active

    defp market_state(_current, _lifecycle, _graduated?, _block, _start), do: :created

    defp pool_id(0), do: nil

    defp pool_id(value) when is_integer(value) and value > 0 do
      "0x" <>
        (value
         |> :binary.encode_unsigned()
         |> Base.encode16(case: :lower)
         |> String.pad_leading(64, "0"))
    end
  end

  defmodule Projector do
    @moduledoc false

    alias AshPlatform.Actors.System, as: SystemActor
    alias AshPlatform.Autolaunch
    alias AshPlatform.Autolaunch.Auction

    def project(snapshots, head) do
      actor = %SystemActor{}
      Ash.DataLayer.transaction(Auction, fn -> project_all(snapshots, actor, head) end)
    end

    defp project_all(snapshots, actor, head) do
      snapshots
      |> Enum.sort_by(& &1.auction_id)
      |> Enum.reduce_while({:ok, []}, fn snapshot, {:ok, changed} ->
        project_snapshot(snapshot, actor, changed)
      end)
      |> case do
        {:ok, changed} ->
          %{
            changed_ids: Enum.reverse(changed),
            block_number: head.block.number,
            block_hash: head.block.hash
          }

        other ->
          other
      end
      |> changed_ids()
    end

    defp project_snapshot(snapshot, actor, changed) do
      case Autolaunch.get_lab_market_auction_for_update(snapshot.auction_id, actor: actor) do
        {:ok, %Auction{} = auction} -> refresh_snapshot(auction, snapshot, actor, changed)
        {:ok, nil} -> rollback(:lab_auction_not_found)
        {:error, reason} -> rollback(reason)
      end
    end

    defp refresh_snapshot(auction, snapshot, actor, changed) do
      state = join_state(auction.state, snapshot.state)
      price = snapshot.current_clearing_price

      if auction.state == state and auction.current_clearing_price == price do
        {:cont, {:ok, changed}}
      else
        refresh_changed_snapshot(auction, state, price, actor, changed)
      end
    end

    defp refresh_changed_snapshot(auction, state, price, actor, changed) do
      case Autolaunch.refresh_lab_market_auction(auction, state, price, actor: actor) do
        {:ok, _auction} -> {:cont, {:ok, [auction.id | changed]}}
        {:error, reason} -> rollback(reason)
      end
    end

    defp changed_ids(%{changed_ids: ids}), do: ids
    defp changed_ids(other), do: other

    defp rollback(reason), do: Ash.DataLayer.rollback(Auction, reason)

    defp join_state(current, _observed) when current in [:graduated, :failed], do: current
    defp join_state(:active, :created), do: :active
    defp join_state(_current, observed), do: observed
  end
end
