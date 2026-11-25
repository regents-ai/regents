defmodule RegentsWeb.SearchLive do
  @moduledoc "The shared workspace dialog for product destinations and public results."

  use Phoenix.LiveView, layout: false, log: false

  alias Phoenix.LiveView.JS
  alias RegentsWeb.{ClientAddress, Docs, Read, RouteCatalog}
  alias RegentsWeb.Components.AppSidebar

  @sources [:docs, :patchbay, :market]

  @doc "Mounts beside the page on routes with the workspace header."
  def dialog(conn) do
    if AppSidebar.workspace?(conn.request_path) do
      outside = %{conn | private: Map.delete(conn.private, :phoenix_live_view)}

      content =
        live_render(outside, __MODULE__,
          container: {:div, class: "shell-search__live"},
          id: "workspace-search",
          session: %{
            "visitor" => ClientAddress.tag(conn),
            "product" => AppSidebar.search_product(conn.request_path, conn.assigns.site_product)
          }
        )

      assigns = %{content: content}

      ~H"""
      <Regent.Structure.dialog id="shell-search" class="shell-search" aria-label="Search all apps">
        {@content}
      </Regent.Structure.dialog>
      """
    end
  end

  @impl true
  def mount(_params, %{"visitor" => visitor, "product" => product}, socket) do
    socket =
      assign(socket,
        visitor: visitor,
        q: "",
        product: normalize_product(product),
        limited?: false,
        docs: %Read{},
        patchbay: %Read{},
        market: %Read{}
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("open", %{"product" => product}, socket),
    do: {:noreply, assign(socket, :product, normalize_product(product))}

  def handle_event("search", %{"q" => q}, socket) when is_binary(q) do
    q = q |> String.trim() |> String.slice(0, 100)

    socket =
      cond do
        String.length(q) < 2 ->
          socket |> assign(q: q, limited?: false) |> clear_search()

        q == socket.assigns.q and not socket.assigns.limited? ->
          socket

        Regents.Limits.spend(:regents_workspace_search, socket.assigns.visitor) == :ok ->
          socket |> assign(q: q, limited?: false) |> start_search(q)

        true ->
          assign(socket, q: q, limited?: true)
      end

    {:noreply, socket}
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  @impl true
  def handle_async({Read, _, _} = name, result, socket),
    do: {:noreply, Read.settle(socket, name, result)}

  defp clear_search(socket) do
    Enum.reduce(@sources, socket, fn key, socket -> Read.clear(socket, key) end)
  end

  defp start_search(socket, q) do
    Enum.reduce(@sources, socket, fn key, socket ->
      Read.start(socket, key, q, fn -> read(key, q) end)
    end)
  end

  defp read(:docs, query), do: Docs.search_matches(query)
  defp read(:patchbay, query), do: RegentsWeb.Patchbay.Search.matches(query)
  defp read(:market, query), do: RegentsWeb.Autolaunch.Search.matches(query)

  defp normalize_product("protocol"), do: "regents"

  defp normalize_product(product) when product in ~w(autolaunch cloak keyfleet patchbay techtree),
    do: product

  defp normalize_product(_product), do: "regents"

  defp shortcuts do
    products =
      for {product, name, _, links} <- AppSidebar.groups(),
          {label, path} <- links do
        %{kind: :page, label: label, path: path, product: product, detail: name}
      end

    account =
      for %{label: label, path: path} <- RouteCatalog.account_tabs() do
        %{kind: :page, label: label, path: path, product: "regents", detail: "Account"}
      end

    products ++ account
  end

  defp results(q, product, others) do
    needle = String.downcase(q)
    words = String.split(needle)

    (shortcuts() ++ others)
    |> Enum.flat_map(fn item ->
      case score(item, needle, words) do
        nil -> []
        score -> [{score + if(item.product == product, do: 4, else: 0), item}]
      end
    end)
    |> Enum.sort_by(&elem(&1, 0), :desc)
    |> Enum.map(&elem(&1, 1))
    |> Enum.uniq_by(& &1.path)
    |> Enum.take(if(q == "", do: 8, else: 16))
  end

  defp score(_item, "", _words), do: 0

  defp score(item, needle, words) do
    label = String.downcase(item.label)
    context = String.downcase(Enum.join([label, item.detail, item.path], " "))

    cond do
      label == needle -> 30
      String.starts_with?(label, needle) -> 18
      Enum.all?(words, &String.contains?(label, &1)) -> 12
      Enum.all?(words, &String.contains?(context, &1)) -> 8
      true -> item[:fallback]
    end
  end

  @impl true
  def render(assigns) do
    reads = Enum.map(@sources, &Map.fetch!(assigns, &1))
    current = Enum.filter(reads, &(&1.owner == assigns.q))
    others = Enum.flat_map(current, &(&1.value || []))

    assigns =
      assign(assigns,
        results: if(assigns.limited?, do: [], else: results(assigns.q, assigns.product, others)),
        loading?: !assigns.limited? and Enum.any?(current, &(&1.state == :loading)),
        unavailable?: !assigns.limited? and Enum.any?(current, &(&1.state in [:error, :stale]))
      )

    ~H"""
    <div id="shell-search-content" class="shell-search__content" phx-hook="WorkspaceSearch">
      <form id="shell-search-form" role="search" phx-change="search" phx-submit="search">
        <Regent.Icons.icon name="search" />
        <input
          id="shell-search-input"
          name="q"
          type="search"
          value={@q}
          role="combobox"
          aria-label="Search all apps"
          aria-expanded="true"
          aria-controls="shell-search-results"
          aria-autocomplete="list"
          autocomplete="off"
          autofocus
          spellcheck="false"
          maxlength="100"
          phx-debounce="200"
          phx-mounted={JS.ignore_attributes(["aria-activedescendant"])}
          placeholder="Search all apps"
        />
        <button
          type="button"
          class="shell-search__close"
          data-search-close
          command="close"
          commandfor="shell-search"
          aria-label="Close search"
        >
          <Regent.Icons.icon name="x" />
        </button>
      </form>
      <div id="shell-search-results" role="listbox" aria-label="Results" data-query={@q}>
        <.link
          :for={{item, index} <- Enum.with_index(@results)}
          id={"shell-search-result-#{index}"}
          href={item.path}
          role="option"
          tabindex="-1"
          aria-selected="false"
          data-search-result
          phx-mounted={JS.ignore_attributes(["aria-selected"])}
        >
          <Regent.Icons.icon name={icon(item.kind)} />
          <span class="shell-search__text">
            <strong>{item.label}</strong>
            <small>{item.detail}</small>
          </span>
          <span class="shell-search__product">{product_name(item.product)}</span>
        </.link>
      </div>
      <p :if={@loading?} class="shell-search__note" role="status">Searching…</p>
      <p :if={@limited?} class="shell-search__note" role="status">
        You’re searching quickly. Wait a moment and try again.
      </p>
      <p :if={@unavailable?} class="shell-search__note" role="status">
        Some results are temporarily unavailable.
      </p>
      <p
        :if={@results == [] and !@loading? and !@unavailable? and !@limited?}
        class="shell-search__note"
        role="status"
      >
        No results for “{@q}”
      </p>
    </div>
    """
  end

  defp icon(:question), do: "message-square"
  defp icon(:doc), do: "book-open"
  defp icon(:market), do: "chart-line"
  defp icon(kind) when kind in [:site, :tool], do: "link"
  defp icon(_), do: "file-text"

  defp product_name("regents"), do: "Regents"
  defp product_name(product), do: String.capitalize(product)
end
