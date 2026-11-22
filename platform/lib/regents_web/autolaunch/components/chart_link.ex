defmodule RegentsWeb.Autolaunch.Components.ChartLink do
  @moduledoc """
  A Base token page's View Chart button, which `TokenHeading` shows once the
  pool is read: DexScreener's chart once DexScreener says it has this pool
  (`Regents.Autolaunch.DexScreener.listed?/1`), and until then, or when it
  says it has none, the page's own price chart (`own_chart`, the chart's id),
  or nothing while the page draws none.

  It asks once, in the background, when it is first shown; the caller's id
  holds the pool id, so the ask has one owner for as long as the button
  stays. It takes no event of its own: one sent to it changes nothing.
  """
  use Phoenix.LiveComponent

  @impl true
  def mount(socket), do: {:ok, assign(socket, asked?: false)}

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    if socket.assigns.asked? do
      {:ok, socket}
    else
      pool_id = socket.assigns.pool_id

      {:ok,
       socket
       |> assign(:asked?, true)
       |> assign_async(:listed, fn ->
         {:ok, %{listed: Regents.Autolaunch.DexScreener.listed?(pool_id)}}
       end)}
    end
  end

  # An event sent to the button changes nothing.
  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <span id={@id} class="token-heading__chart">
      <a
        :if={@listed.ok? && @listed.result == true}
        class="rg-button rg-button--secondary token-heading__link"
        href={"https://dexscreener.com/base/#{@pool_id}"}
        target="_blank"
        rel="noopener noreferrer"
      >
        <span class="token-heading__dexscreener" aria-hidden="true"></span> View Chart
      </a>
      <a
        :if={(!@listed.ok? || @listed.result != true) && @own_chart}
        class="rg-button rg-button--secondary token-heading__link"
        href={"#" <> @own_chart}
      >
        View Chart
      </a>
    </span>
    """
  end
end
