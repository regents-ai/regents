defmodule AshPlatformWeb.ShellLive.Redemption do
  @moduledoc """
  The Redeem page's reading of Base for the chosen Animata and wallet, and the
  panel of collectibles that wallet holds. Each Base read is numbered; only the
  latest one lands, and only while the Redeem page is open. A read the page
  stops waiting for is left to finish and its answer is dropped.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [connected?: 1, start_async: 3]

  alias AshPlatform.{OpenSea, Redemption}
  alias AshPlatform.OpenSea.HoldingsCache
  alias AshPlatform.Redemption.Steps
  alias AshPlatformWeb.EventInput
  alias AshPlatformWeb.ShellLive.{Identity, OpenSeaBudget}

  @refresh_failure_notice "Couldn’t update just now. The figures shown are from the last successful reading."
  @collections ~w(animata_i animata_ii)
  # Longer than any collection or token ID; the token ID input stops there too.
  @selection_limits %{"collection" => 16, "token_id" => 16}
  @collectibles_page 24

  @events ~w(redemption_selection_changed refresh_redemption select_owned_animata show_more_collectibles)

  def handles?(event), do: event in @events

  def init(socket) do
    socket
    |> assign(
      redemption_collection: "animata_i",
      redemption_token_id: "",
      redemption_generation: 0
    )
    |> cleared()
  end

  def route(socket, %{route_id: :redeem}) do
    socket = assign(socket, redemption_wallet: Identity.position_wallet(socket.assigns))

    if connected?(socket),
      do: start_redemption_read(socket, lookup_owned: true),
      else: socket
  end

  def route(socket, _route_spec), do: socket |> forget_redemption_read() |> cleared()

  defp cleared(socket) do
    assign(socket,
      redemption: nil,
      redemption_status: :loading,
      redemption_refresh_block: nil,
      redemption_notice: nil,
      redemption_read: nil,
      redemption_snapshot_selection: nil,
      redemption_wallet: nil,
      owned_collectibles: idle_collectibles(),
      owned_collectibles_limit: @collectibles_page,
      open_sea_lookup: nil
    )
  end

  def reading?(%{redemption_read: nil}), do: false
  def reading?(_assigns), do: true

  def step(assigns) do
    if selection_ready?(assigns),
      do: Redemption.next_step(assigns.redemption, assigns.redemption_wallet),
      else: nil
  end

  def settle(
        %{assigns: %{route_spec: %{route_id: :redeem}, redemption_generation: generation}} =
          socket,
        {:redemption, generation} = name,
        {:ok, {:ok, redemption}}
      ) do
    read = socket.assigns.redemption_read

    refresh_block =
      case read do
        %{name: ^name, announce_refresh: true} -> redemption.block_number
        _ -> socket.assigns.redemption_refresh_block
      end

    socket
    |> release_redemption_read(name)
    |> assign(
      redemption: redemption,
      redemption_status: :ready,
      redemption_refresh_block: refresh_block,
      redemption_snapshot_selection: current_selection(socket.assigns)
    )
    |> maybe_start_open_sea_lookup(match?(%{name: ^name, lookup_owned: true}, read))
  end

  # A failed or crashed read answered nothing about Base. Release the refresh
  # control and preserve an existing snapshot; only an initial read has no data
  # to retain.
  def settle(
        %{assigns: %{route_spec: %{route_id: :redeem}, redemption_generation: generation}} =
          socket,
        {:redemption, generation} = name,
        _failed
      ),
      do: socket |> release_redemption_read(name) |> redemption_read_failed()

  # A read whose page has since moved on still releases its own marker, so the
  # refresh control is never left disabled by a read nobody is waiting for.
  def settle(socket, {:redemption, _generation} = name, _result),
    do: release_redemption_read(socket, name)

  def settle(
        %{
          assigns: %{
            route_spec: %{route_id: :redeem},
            redemption_wallet: wallet,
            open_sea_lookup: name
          }
        } = socket,
        {:open_sea, wallet} = name,
        {:ok, {:ok, items}}
      ) do
    status = if items.animata == [] and items.regents_club == [], do: :empty, else: :ready
    assign(socket, open_sea_lookup: nil, owned_collectibles: Map.put(items, :status, status))
  end

  def settle(%{assigns: %{open_sea_lookup: name}} = socket, {:open_sea, _wallet} = name, _failed),
    do:
      assign(socket,
        open_sea_lookup: nil,
        owned_collectibles: Map.put(socket.assigns.owned_collectibles, :status, :unavailable)
      )

  def settle(socket, {:open_sea, _wallet}, _result), do: socket

  # A control from a page that has since moved on changes nothing.
  def handle_event(_event, _params, %{assigns: %{route_spec: %{route_id: route_id}}} = socket)
      when route_id != :redeem,
      do: socket

  def handle_event("redemption_selection_changed", params, socket) do
    case EventInput.texts(params, @selection_limits) do
      {:ok, fields} ->
        select(
          socket,
          Map.get(fields, "collection", socket.assigns.redemption_collection),
          Map.get(fields, "token_id", "")
        )

      :error ->
        unreadable(socket)
    end
  end

  def handle_event("select_owned_animata", params, socket) do
    case EventInput.texts(params, %{"collection" => 16, "token-id" => 16}) do
      {:ok, %{"collection" => collection, "token-id" => token_id}} ->
        select(socket, collection, token_id)

      _unreadable ->
        unreadable(socket)
    end
  end

  def handle_event("refresh_redemption", _params, socket), do: refresh(socket, false)

  def handle_event("show_more_collectibles", _params, socket) do
    total =
      length(socket.assigns.owned_collectibles.animata) +
        length(socket.assigns.owned_collectibles.regents_club)

    assign(socket,
      owned_collectibles_limit:
        min(socket.assigns.owned_collectibles_limit + @collectibles_page, total)
    )
  end

  @doc """
  The Redeem buttons heard which wallet Privy has active; the figures follow
  it on the same terms as Stake's.
  """
  def active_wallet(%{assigns: %{route_spec: %{route_id: :redeem}}} = socket, active) do
    socket = assign(socket, browser_wallet: active)
    wallet = Identity.position_wallet(socket.assigns)

    if wallet == socket.assigns.redemption_wallet,
      do: socket,
      else: adopt_wallet(socket, wallet)
  end

  def active_wallet(socket, _active), do: socket

  @doc """
  A Redeem step landed: the figures are read again, and after a redemption
  the collection too.
  """
  def step_landed(%{assigns: %{route_spec: %{route_id: :redeem}}} = socket, name),
    do: refresh(socket, name == "redeem")

  def step_landed(socket, _name), do: socket

  # Only the two collections are ever chosen; the token ID is read as typed.
  defp select(socket, collection, token_id) when collection in @collections do
    socket
    |> assign(
      redemption_collection: collection,
      redemption_token_id: token_id,
      redemption_notice: nil
    )
    |> read_selection()
  end

  defp select(socket, _collection, _token_id), do: unreadable(socket)

  defp unreadable(socket),
    do: assign(socket, redemption_notice: %{tone: :error, message: EventInput.unreadable()})

  # A landed redemption is the one moment the collection on screen is known to
  # be out of date. The cache honours one such reset per wallet per cache
  # window, so repeated landings buy no extra reads.
  defp refresh(socket, refresh_owned) do
    socket =
      if refresh_owned and is_binary(socket.assigns.redemption_wallet) do
        HoldingsCache.invalidate(socket.assigns.redemption_wallet)

        assign(socket,
          open_sea_lookup: nil,
          owned_collectibles: Map.put(socket.assigns.owned_collectibles, :status, :refreshing)
        )
      else
        socket
      end

    start_redemption_read(socket,
      preserve_snapshot: true,
      announce_refresh: true,
      lookup_owned: true
    )
  end

  defp start_redemption_read(socket, options) do
    generation = socket.assigns.redemption_generation + 1
    name = {:redemption, generation}
    wallet = socket.assigns.redemption_wallet
    collection = socket.assigns.redemption_collection
    token_id = parsed_token_id(socket.assigns.redemption_token_id)

    preserve_snapshot =
      Keyword.get(options, :preserve_snapshot, false) && not is_nil(socket.assigns.redemption)

    announce_refresh = Keyword.get(options, :announce_refresh, false)

    socket
    |> assign(
      redemption: if(preserve_snapshot, do: socket.assigns.redemption),
      redemption_status: if(preserve_snapshot, do: :ready, else: :loading),
      redemption_refresh_block:
        if(announce_refresh, do: nil, else: socket.assigns.redemption_refresh_block),
      redemption_notice: if(announce_refresh, do: nil, else: socket.assigns.redemption_notice),
      redemption_generation: generation,
      redemption_read: %{
        name: name,
        selection: {collection, token_id},
        announce_refresh: announce_refresh,
        lookup_owned: Keyword.get(options, :lookup_owned, false)
      }
    )
    |> start_async(name, fn ->
      if wallet,
        do: Redemption.account_for_wallet(wallet, collection, token_id),
        else: Redemption.overview()
    end)
  end

  # The page stops waiting for the read in flight: moving to the next number
  # means its answer, whenever it comes, no longer lands.
  defp forget_redemption_read(socket) do
    assign(socket,
      redemption_read: nil,
      redemption_generation: socket.assigns.redemption_generation + 1
    )
  end

  # A keystroke that leaves the selection Base was asked about unchanged buys
  # no read: the reading in flight or the snapshot on screen already answers
  # it. Only a selection neither of them covers is read.
  defp read_selection(socket) do
    selection = current_selection(socket.assigns)

    cond do
      match?(%{selection: ^selection}, socket.assigns.redemption_read) -> socket
      selection_ready?(socket.assigns) -> forget_redemption_read(socket)
      true -> start_redemption_read(socket, preserve_snapshot: true)
    end
  end

  defp adopt_wallet(socket, wallet) do
    socket
    |> assign(
      redemption_wallet: wallet,
      redemption: public_snapshot(socket.assigns.redemption),
      redemption_status: if(socket.assigns.redemption, do: :ready, else: :loading),
      redemption_refresh_block: nil,
      redemption_notice: nil,
      redemption_snapshot_selection: nil,
      owned_collectibles: idle_collectibles(),
      owned_collectibles_limit: @collectibles_page,
      open_sea_lookup: nil
    )
    |> start_redemption_read(preserve_snapshot: true, lookup_owned: true)
  end

  defp redemption_read_failed(socket) do
    collectibles =
      case socket.assigns.owned_collectibles do
        %{status: :refreshing} = current -> Map.put(current, :status, :unavailable)
        current -> current
      end

    if socket.assigns.redemption do
      assign(socket,
        redemption_status: :ready,
        owned_collectibles: collectibles,
        redemption_notice: %{tone: :error, message: @refresh_failure_notice}
      )
    else
      assign(socket,
        redemption: nil,
        redemption_status: :error,
        owned_collectibles: collectibles,
        redemption_snapshot_selection: nil
      )
    end
  end

  defp release_redemption_read(%{assigns: %{redemption_read: %{name: name}}} = socket, name),
    do: assign(socket, redemption_read: nil)

  defp release_redemption_read(socket, _name), do: socket

  defp selection_ready?(assigns) do
    not is_nil(assigns.redemption) and
      assigns.redemption_snapshot_selection == current_selection(assigns)
  end

  defp current_selection(assigns),
    do: {assigns.redemption_collection, parsed_token_id(assigns.redemption_token_id)}

  # Editing a token ID re-reads Base, but it says nothing new about which
  # collectibles the wallet holds. Only a wallet change or an explicit refresh
  # asks for the collection again, so typing never spends the page's share of
  # lookups and an outage cannot cost a visitor the panel for the rest of a
  # minute.
  defp maybe_start_open_sea_lookup(socket, true), do: start_open_sea_lookup(socket)
  defp maybe_start_open_sea_lookup(socket, false), do: socket

  # A lookup past this connection's OpenSea share is shown as unavailable: the
  # manual collection and token ID fields stay open and no wallet action is
  # refused.
  defp start_open_sea_lookup(
         %{assigns: %{redemption_wallet: wallet, owned_collectibles: %{status: status}}} = socket
       )
       when is_binary(wallet) and status in [:idle, :unavailable, :refreshing] do
    case OpenSeaBudget.claim(socket) do
      {:limited, socket} ->
        assign(socket,
          owned_collectibles: Map.put(socket.assigns.owned_collectibles, :status, :unavailable)
        )

      {:ok, socket} ->
        name = {:open_sea, wallet}

        socket
        |> assign(
          open_sea_lookup: name,
          owned_collectibles: loading_collectibles(socket.assigns.owned_collectibles)
        )
        |> start_async(name, fn -> OpenSea.fetch_owned_collectibles(wallet) end)
    end
  end

  defp start_open_sea_lookup(socket), do: socket

  defp idle_collectibles, do: %{status: :idle, animata: [], regents_club: []}

  defp loading_collectibles(%{status: :idle}),
    do: %{status: :loading, animata: [], regents_club: []}

  defp loading_collectibles(collectibles), do: collectibles

  defp parsed_token_id(value) do
    case Steps.token_id(value) do
      {:ok, token_id} -> token_id
      :error -> nil
    end
  end

  defp public_snapshot(nil), do: nil

  defp public_snapshot(redemption) do
    Map.merge(redemption, %{
      wallet_address: nil,
      selected_collection: nil,
      token_id: nil,
      nft_owner: nil,
      nft_redeemed: false,
      nft_owner_unavailable: false,
      nft_approved: nil,
      usdc_balance_raw: nil,
      usdc_balance: nil,
      usdc_allowance_raw: nil,
      usdc_allowance: nil,
      claimable_raw: nil,
      claimable: nil,
      vest_pool_raw: nil,
      vest_pool: nil,
      vest_released_raw: nil,
      vest_released: nil,
      vest_claimed_raw: nil,
      vest_claimed: nil,
      vest_start: nil
    })
  end
end
