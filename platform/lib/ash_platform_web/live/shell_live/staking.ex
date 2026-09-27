defmodule AshPlatformWeb.ShellLive.Staking do
  @moduledoc """
  The staking figures on the Stake and operations pages. The contract reading
  is shared by every visitor and arrives from `SnapshotCache`; each page adds
  its own wallet's figures, read at their own block and set beside the shared
  reading rather than over it.

  Only those two pages hear new contract readings, and each read belongs to
  the visit that started it: a wallet reading that lands after the page moved
  on is dropped.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [connected?: 1, start_async: 3]

  alias AshPlatform.Actors.Human
  alias AshPlatform.Staking
  alias AshPlatform.Staking.Facts, as: StakingFacts
  alias AshPlatform.Staking.SnapshotCache
  alias AshPlatformWeb.ShellLive.Identity

  @routes [:stake, :app]
  @refresh_failure_notice "Couldn’t update just now. The figures shown are from the last successful reading."
  # Names the budget it belongs to. The Redeem page has its own, unrelated
  # per-visitor limit on looking up owned NFTs, and the two refusals must never
  # read as the same thing.
  @shared_refresh_budget_notice "Contract data was refreshed for everyone moments ago. Ask for a new reading again in a few seconds."

  def init(socket) do
    assign(socket,
      staking: nil,
      staking_wallet: nil,
      staking_notice: nil,
      staking_read: nil,
      staking_shared_reading: false,
      staking_status: :loading,
      staking_generation: 0,
      staking_followed: false
    )
  end

  def route(socket, route_spec) do
    socket
    |> assign(staking_generation: socket.assigns.staking_generation + 1)
    |> enter(route_spec)
  end

  # The disconnected HTTP render can use the server cache immediately. Never
  # start a chain or per-wallet request there; those remain asynchronous after
  # connection, and no private wallet facts enter this shared projection.
  defp enter(socket, %{route_id: :stake}) do
    socket = assign(socket, staking_wallet: Identity.position_wallet(socket.assigns))

    if connected?(socket),
      do: socket |> follow_snapshots() |> paint_shared_snapshot() |> start_staking_read(),
      else: paint_shared_snapshot(socket, :loading)
  end

  # An anonymous visitor to either page buys no chain read at all: the shared
  # contract reading is already on the server and is painted as it is. Only a
  # signed-in account has a wallet to look up here, and that lookup takes its
  # own fresh block.
  defp enter(socket, %{route_id: :app}) do
    if connected?(socket) do
      socket
      |> follow_snapshots()
      |> clear_staking_wallet()
      |> paint_shared_snapshot()
      |> read_account_wallet()
    else
      paint_shared_snapshot(socket, :loading)
    end
  end

  defp enter(socket, _route_spec) do
    socket
    |> unfollow_snapshots()
    |> clear_staking_wallet()
    |> assign(
      staking: nil,
      staking_status: :loading,
      staking_read: nil,
      staking_shared_reading: false
    )
  end

  defp follow_snapshots(%{assigns: %{staking_followed: true}} = socket), do: socket

  defp follow_snapshots(socket) do
    Phoenix.PubSub.subscribe(AshPlatform.PubSub, SnapshotCache.topic())
    assign(socket, staking_followed: true)
  end

  defp unfollow_snapshots(%{assigns: %{staking_followed: false}} = socket), do: socket

  defp unfollow_snapshots(socket) do
    Phoenix.PubSub.unsubscribe(AshPlatform.PubSub, SnapshotCache.topic())
    assign(socket, staking_followed: false)
  end

  def reading?(%{staking_read: nil}), do: false
  def reading?(_assigns), do: true

  @doc """
  A wallet reading answers for one account at its own block and says nothing
  about the contract, so it is set beside the shared reading rather than over
  it. A failed or crashed wallet read leaves the contract reading exactly where
  it is and marks only this wallet's own figures unavailable; the page keeps
  its layout and every control on it.
  """
  def settle(
        %{assigns: %{staking_generation: generation, staking: staking}} = socket,
        {:staking, generation} = name,
        {:ok, {:ok, wallet_facts}}
      )
      when is_map(staking) do
    socket
    |> release_staking_read(name)
    |> assign(
      staking: StakingFacts.merge(staking, wallet_facts),
      staking_status: :ready,
      staking_notice: clear_staking_refresh_failure(socket.assigns.staking_notice)
    )
  end

  def settle(
        %{assigns: %{staking_generation: generation}} = socket,
        {:staking, generation} = name,
        _failed
      ),
      do: socket |> release_staking_read(name) |> wallet_read_failed()

  def settle(socket, name, _result), do: release_staking_read(socket, name)

  @doc """
  One visitor's refresh re-reads the contract for everyone. Only the contract
  figures are replaced: each page keeps whatever it knows about its own
  connected wallet, still labelled with the block that wallet was read at, and
  a wallet already answered for is never re-read on its own.
  """
  def snapshot(%{assigns: %{route_spec: %{route_id: route_id}}} = socket, protocol)
      when route_id in @routes do
    socket
    |> assign(
      staking: StakingFacts.adopt_protocol(socket.assigns.staking, protocol),
      staking_shared_reading: false,
      staking_status: :ready
    )
    |> read_unanswered_wallet()
  end

  def snapshot(socket, _protocol), do: socket

  @doc """
  Only the page that asked for the reading hears that it failed, and what it
  was already showing stays on screen.
  """
  def snapshot_unavailable(%{assigns: %{route_spec: %{route_id: route_id}}} = socket)
      when route_id in @routes,
      do: socket |> assign(staking_shared_reading: false) |> shared_read_failed()

  def snapshot_unavailable(socket), do: socket

  @doc """
  The Stake actions heard which wallet Privy has active. Signed in, the figures
  follow it when it is the account's own; any other wallet leaves them on the
  account's first wallet while the actions ask the person to switch.
  """
  def active_wallet(%{assigns: %{route_spec: %{route_id: :stake}}} = socket, active) do
    socket = assign(socket, browser_wallet: active)
    wallet = Identity.position_wallet(socket.assigns)

    if wallet == socket.assigns.staking_wallet,
      do: socket,
      else: adopt_staking_wallet(socket, wallet)
  end

  def active_wallet(socket, _active), do: socket

  @doc "A Stake step landed: this wallet's figures moved, so they are read again."
  def step_landed(%{assigns: %{route_spec: %{route_id: :stake}}} = socket),
    do: start_staking_read(socket)

  def step_landed(socket), do: socket

  def handle_event(
        "refresh_shared_snapshot",
        %{assigns: %{route_spec: %{route_id: route_id}}} = socket
      )
      when route_id in @routes,
      do: read_shared_snapshot(socket)

  # The Stake footer asks for both readings at once, on the same terms each is
  # asked for on its own.
  def handle_event("refresh_data", %{assigns: %{route_spec: %{route_id: route_id}}} = socket)
      when route_id in @routes,
      do: socket |> start_staking_read() |> read_shared_snapshot()

  # A control from a page that has since moved on changes nothing.
  def handle_event(_event, socket), do: socket

  # With no successful shared reading yet, there is nothing honest to show and
  # nothing this visitor can do about it alone; the page says so and a signed-in
  # visitor is offered the control that takes one.
  defp paint_shared_snapshot(socket, empty_status \\ :error) do
    case SnapshotCache.snapshot() do
      nil ->
        assign(socket, staking: nil, staking_status: empty_status)

      protocol ->
        assign(socket,
          staking: StakingFacts.merge(protocol, StakingFacts.blank_wallet()),
          staking_status: :ready
        )
    end
  end

  defp clear_staking_wallet(socket), do: assign(socket, staking_wallet: nil, staking_notice: nil)

  # A wallet reading that failed leaves every figure it would have carried
  # marked unavailable, beside the contract reading it never spoke about. With
  # no contract reading to sit beside there is nothing to mark.
  defp wallet_read_failed(%{assigns: %{staking: nil}} = socket), do: shared_read_failed(socket)

  defp wallet_read_failed(socket) do
    assign(socket,
      staking:
        StakingFacts.merge(
          socket.assigns.staking,
          StakingFacts.unavailable_wallet(socket.assigns.staking_wallet)
        ),
      staking_status: :ready,
      staking_notice: %{tone: :error, message: @refresh_failure_notice}
    )
  end

  # Only the contract reading can leave a page with nothing honest to show. A
  # reading that fails leaves the previous one exactly where it was.
  defp shared_read_failed(socket) do
    if socket.assigns.staking do
      assign(socket,
        staking_status: :ready,
        staking_notice: %{tone: :error, message: @refresh_failure_notice}
      )
    else
      assign(socket, staking: nil, staking_status: :error)
    end
  end

  defp clear_staking_refresh_failure(%{message: @refresh_failure_notice}), do: nil
  defp clear_staking_refresh_failure(notice), do: notice

  # Re-reading the contract replaces what every visitor sees, so only a
  # signed-in session may ask for it, and the socket's own session decides that
  # here rather than the markup that offered the control.
  defp read_shared_snapshot(socket) do
    if Identity.authenticated?(socket.assigns.access_context) do
      request_shared_refresh(socket)
    else
      socket
    end
  end

  defp request_shared_refresh(socket) do
    case SnapshotCache.refresh() do
      :ok ->
        assign(socket, staking_shared_reading: true, staking_notice: nil)

      {:error, :refresh_too_soon} ->
        assign(socket, staking_notice: %{tone: :info, message: @shared_refresh_budget_notice})
    end
  end

  # A wallet connected while there was no contract reading has nothing to be
  # shown beside, so nothing was bought for it. The moment a contract reading
  # arrives that wallet is looked up, rather than leaving somebody to ask for a
  # reading they already asked for. A wallet the page has an answer for, however
  # that answer turned out, is left alone.
  # The Overview reads the signed-in account's own wallet, so one never read
  # because the contract reading was missing is read once that reading arrives.
  defp read_unanswered_wallet(
         %{
           assigns: %{
             route_spec: %{route_id: :app},
             staking: %{wallet_block_number: nil},
             staking_read: nil
           }
         } = socket
       ),
       do: read_account_wallet(socket)

  defp read_unanswered_wallet(%{assigns: %{staking_wallet: nil}} = socket), do: socket

  defp read_unanswered_wallet(
         %{assigns: %{staking: %{wallet_address: wallet}, staking_wallet: wallet}} = socket
       ),
       do: socket

  defp read_unanswered_wallet(socket), do: start_staking_read(socket)

  defp read_account_wallet(socket) do
    case Identity.current_account(socket.assigns.access_context) do
      nil ->
        socket

      account ->
        actor = %Human{human_account_id: account.id}
        start_wallet_read(socket, fn -> Staking.account(actor: actor) end)
    end
  end

  # This socket's own connected wallet, read again at a fresh block. Any
  # connected wallet may do this, signed in or not. With no wallet connected
  # there is nothing about this visitor to read, and the shared contract
  # reading on screen already answers for everyone.
  defp start_staking_read(%{assigns: %{staking_wallet: nil}} = socket), do: socket

  defp start_staking_read(socket) do
    wallet = socket.assigns.staking_wallet
    start_wallet_read(socket, fn -> Staking.account_for_wallet(wallet) end)
  end

  # A wallet reading answers for one account and carries no contract figures, so
  # with no shared reading on screen there is nothing for it to be shown beside.
  # Buying one anyway spends four round trips on an answer that would be thrown
  # away, so it is not bought until the contract reading is there. A read
  # started again under the same name replaces the one running, whose answer
  # LiveView then drops.
  defp start_wallet_read(%{assigns: %{staking: nil}} = socket, _read), do: socket

  defp start_wallet_read(socket, read) do
    name = {:staking, socket.assigns.staking_generation}

    socket
    |> assign(staking_read: %{name: name})
    |> start_async(name, read)
  end

  defp release_staking_read(%{assigns: %{staking_read: %{name: name}}} = socket, name),
    do: assign(socket, staking_read: nil)

  defp release_staking_read(socket, _name), do: socket

  # A different wallet's position is not this one's. The contract reading stays
  # exactly as it is while the new wallet is looked up at its own fresh block.
  defp adopt_staking_wallet(socket, wallet) do
    socket
    |> assign(
      staking: forget_wallet_facts(socket.assigns.staking),
      staking_wallet: wallet,
      staking_notice: nil
    )
    |> start_staking_read()
  end

  defp forget_wallet_facts(nil), do: nil
  defp forget_wallet_facts(staking), do: StakingFacts.merge(staking, StakingFacts.blank_wallet())
end
