defmodule RegentsWeb.Autolaunch.LiveListings do
  @moduledoc """
  The auctions and tokens lists' records (`paged/1`): read for the page's
  filters (`filtered/3`) and a page more at a time (`load/2`). The reads'
  answers land here, never in the page.

  Opening a page is one of its address's reads of the site, as any page is.
  Each listing an open Autolaunch page then reads, the home page's included,
  spends one of that address's `:autolaunch_list_reads` (`admit/1`,
  `Regents.Limits`); past the allowance the page shows its failed notice. A
  list page's first listing also starts, in the background and under that
  one spend, the dollar prices (`Regents.Autolaunch.UsdRates`) and the
  page's own other reads; when the allowance is spent none of them is read,
  and each is failed. A token's page reads its parts the same way, under one
  spend (`spend/2`).

  Still to come: the lists rereading themselves while the page is open.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [assign_async: 3, attach_hook: 4, connected?: 1, start_async: 3]

  alias Phoenix.LiveView.AsyncResult
  alias Regents.Autolaunch.UsdRates
  alias Regents.Limits
  alias RegentsWeb.Autolaunch.HomeMarket

  @doc """
  Spends one of the address's `:autolaunch_list_reads` for a listing the open
  page reads: `:ok`, or `:limited` once the allowance is spent. The visit's
  own request is counted with the address's reads of the site, so the page's
  first render spends none.
  """
  def admit(socket) do
    if connected?(socket),
      do: Limits.spend(:autolaunch_list_reads, socket.assigns.client_tag),
      else: :ok
  end

  @doc """
  Starts each of `reads`, `{assign, read}` where `read` answers `{:ok, value}`
  or `{:error, reason}`, in the background under one spend (`admit/1`):
  `{:ok, socket}` with each one loading, or `{:limited, socket}` once the
  allowance is spent, with none of them read and each failed as
  `{:error, :limited}`.
  """
  def spend(socket, reads) do
    case admit(socket) do
      :ok ->
        {:ok,
         Enum.reduce(reads, socket, fn {key, read}, socket -> start_read(socket, key, read) end)}

      :limited ->
        {:limited,
         Enum.reduce(reads, socket, fn {key, _read}, socket -> refused(socket, key) end)}
    end
  end

  @doc """
  One page of the list `options` name after `cursor`, with its creators'
  connected accounts (`Regents.Autolaunch.HomeMarket.creators/1`) as
  `:creators`. A failed accounts read fails the listing.
  """
  def read(options, cursor) do
    with {:ok, page} <- HomeMarket.read(options, cursor),
         {:ok, creators} <- Regents.Autolaunch.HomeMarket.creators(page.records) do
      {:ok, Map.put(page, :creators, creators)}
    end
  end

  @doc "A list page's records, empty until its first `filtered/3`."
  def paged(socket) do
    socket
    |> assign(
      options: nil,
      records: [],
      creators: %{},
      loading: true,
      failed: false,
      append: false,
      next_cursor: nil,
      has_more: false
    )
    |> attach_hook(:listings, :handle_async, &answered/3)
  end

  @doc """
  Reads the list from its start for `options`, unless it already shows them.
  The page's first listing also starts the dollar prices as `:rates` and each
  of `reads`, `{assign, read}` where `read` answers `{:ok, value}` or
  `{:error, reason}`, every one under the listing's one spend.
  """
  def filtered(socket, options, reads \\ [])
  def filtered(%{assigns: %{options: options}} = socket, options, _reads), do: socket

  def filtered(%{assigns: %{options: nil}} = socket, options, reads),
    do:
      socket
      |> assign(:options, options)
      |> listing(false, [{:rates, fn -> {:ok, UsdRates.rates()} end} | reads])

  def filtered(socket, options, _reads), do: socket |> assign(:options, options) |> load(false)

  @doc "Reads the list from its start, or its next page with `append?`."
  def load(socket, append?), do: listing(socket, append?, [])

  defp listing(socket, append?, reads) do
    %{options: options, next_cursor: next_cursor} = socket.assigns
    cursor = if append?, do: next_cursor

    socket =
      if append?, do: socket, else: assign(socket, records: [], has_more: false, next_cursor: nil)

    socket = assign(socket, :append, append?)

    case spend(socket, reads) do
      {:ok, socket} ->
        socket
        |> assign(loading: true, failed: false)
        |> start_async(:listings, fn -> read(options, cursor) end)

      {:limited, socket} ->
        assign(socket, loading: false, failed: true)
    end
  end

  defp start_read(socket, key, read),
    do:
      assign_async(socket, key, fn -> with {:ok, value} <- read.(), do: {:ok, %{key => value}} end)

  defp refused(socket, key),
    do: assign(socket, key, AsyncResult.failed(AsyncResult.loading(), {:error, :limited}))

  # A listing counts only while the page is waiting for one. A change the
  # allowance refused since the read began has already answered for the list
  # the page now names, so that read's late answer is dropped.
  defp answered(:listings, _answer, %{assigns: %{loading: false}} = socket), do: {:halt, socket}

  defp answered(:listings, {:ok, {:ok, page}}, socket) do
    %{append: append, records: records, creators: creators} = socket.assigns

    {:halt,
     assign(socket,
       records:
         if(append, do: Enum.uniq_by(records ++ page.records, & &1.id), else: page.records),
       creators: if(append, do: Map.merge(creators, page.creators), else: page.creators),
       next_cursor: page.next_cursor,
       has_more: page.has_more,
       loading: false,
       failed: false
     )}
  end

  defp answered(:listings, _failure, socket),
    do: {:halt, assign(socket, loading: false, failed: true)}

  defp answered(_name, _answer, socket), do: {:cont, socket}

  @doc "Subscribes a connected socket to live listing changes."
  def subscribe(socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Regents.PubSub, "autolaunch:listings")
    socket
  end

  @doc "Marks the listing as taken so no scheduled reread is pending."
  def taken(socket), do: assign(socket, :listings_reread_timer, nil)

  @doc "Schedules a debounced reread of the current listing."
  def schedule(socket) do
    if socket.assigns[:listings_reread_timer] do
      socket
    else
      ref = Process.send_after(self(), :reread_listings, 500)
      assign(socket, :listings_reread_timer, ref)
    end
  end

  @doc "Rereads the currently shown listing page without resetting scroll."
  def reread(%{assigns: %{options: nil}} = socket), do: socket

  def reread(%{assigns: %{options: options, records: records}} = socket) do
    count = max(length(records), 24)

    start_async(socket, :listings, fn ->
      with {:ok, page} <- HomeMarket.reread(options, count),
           {:ok, creators} <- Regents.Autolaunch.HomeMarket.creators(page.records) do
        {:ok, Map.put(page, :creators, creators)}
      end
    end)
  end
end
