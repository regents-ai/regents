defmodule RegentsWeb.Patchbay.SiteDirectoryLive do
  @moduledoc """
  The public site directory. A row's Tools are what Patchbay's own check
  found on the pages the listing names for it, or "Not checked" before a
  check of the site has finished (`Regents.Patchbay.Forum.SiteDirectory`). A
  row opens on the picture Patchbay took of the site's home page and those
  tools, and changes as Patchbay's checks of its sites finish
  (`Regents.Patchbay.Forum.SiteCheck.topic/1`; nothing tells that topic yet:
  the checks come with Patchbay's background work).

  Drawn with the page, the directory takes the page the page already read;
  it reads it itself once when it joins. A read that fails as it joins says
  so in the directory's place, with a link that opens the page again; one
  that fails loading more sites says so by the button and keeps the list.
  Each further page spends one of its address's directory reads
  (`patchbay_directory_reads`, `Regents.Limits`); past them the button says
  so in the same words, and nothing is read.
  """
  use RegentsWeb, :live_view

  require Logger

  import RegentsWeb.Patchbay.Forum.BoardHTML,
    only: [domain_path: 1, picture_url: 1, section_unavailable: 1, web_link: 1]

  alias Regents.Limits
  alias Regents.Patchbay.Forum.SiteCheck
  alias Regents.Patchbay.Forum.SiteDirectory
  alias RegentsWeb.Patchbay.Forum.Board

  @impl true
  def mount(_params, %{"filters" => filters, "client_tag" => client_tag}, socket) do
    socket = assign_new(socket, :directory, fn -> read_directory(filters) end)

    case socket.assigns.directory do
      :unavailable ->
        {:ok, assign(socket, retry: ~p"/patchbay/sites?#{filters}"), layout: false}

      page ->
        {:ok,
         socket
         |> assign(
           client_tag: client_tag,
           directory: nil,
           page: page,
           more_failed: false,
           expanded: MapSet.new(),
           subscribed: MapSet.new()
         )
         |> stream_configure(:sites, dom_id: &"directory-#{&1.host}")
         |> stream(:sites, page.sites)
         |> subscribe_sites(page.sites), layout: false}
    end
  end

  defp read_directory(filters) do
    case SiteDirectory.page(filters) do
      {:ok, page} -> page
      {:error, failure} -> failed(failure)
    end
  end

  # A read that fails is logged by its kind only.
  defp failed(failure) do
    Logger.warning(
      "The site directory could not be read: " <> inspect(Board.failure_kind(failure))
    )

    :unavailable
  end

  # A directory that could not be read takes no presses until it is opened
  # again; any press sent by hand changes nothing.
  @impl true
  def handle_event(_event, _params, %{assigns: %{retry: _retry}} = socket),
    do: {:noreply, socket}

  def handle_event("load-more", _params, socket) do
    page = socket.assigns.page

    if page.page < page.pages do
      socket |> read_next(page) |> more(socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle", %{"host" => host}, socket) do
    expanded = socket.assigns.expanded

    expanded =
      cond do
        MapSet.member?(expanded, host) -> MapSet.delete(expanded, host)
        Enum.any?(socket.assigns.page.sites, &(&1.host == host)) -> MapSet.put(expanded, host)
        true -> expanded
      end

    socket = assign(socket, expanded: expanded)
    site = Enum.find(socket.assigns.page.sites, &(&1.host == host))
    {:noreply, if(site, do: stream_insert(socket, :sites, site), else: socket)}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # The page after `page`, spending one of the address's directory reads.
  # Past them nothing is read, and the refusal is not logged.
  defp read_next(socket, page) do
    case Limits.spend(:patchbay_directory_reads, socket.assigns.client_tag) do
      :ok ->
        read_directory(%{
          "q" => page.q,
          "category" => page.category,
          "page" => to_string(page.page + 1)
        })

      :limited ->
        :unavailable
    end
  end

  # The next page joins the list; one that could not be read, or was past the
  # address's reads, says so by the button, which reads it again.
  defp more(:unavailable, socket), do: {:noreply, assign(socket, more_failed: true)}

  defp more(next, socket) do
    page = socket.assigns.page

    {:noreply,
     socket
     |> assign(page: %{next | sites: page.sites ++ next.sites}, more_failed: false)
     |> stream(:sites, next.sites)
     |> subscribe_sites(next.sites)}
  end

  @impl true
  def handle_info(%Ash.Notifier.Notification{data: check}, socket) do
    page = SiteDirectory.replace_check(socket.assigns.page, check)
    socket = assign(socket, page: page)
    {:noreply, stream(socket, :sites, Enum.filter(page.sites, &(&1.domain == check.domain)))}
  end

  @impl true
  def render(%{retry: _retry} = assigns) do
    ~H"""
    <section id="site-directory" class="pb-site-directory" aria-labelledby="directory-heading">
      <header class="pb-directory-intro">
        <div>
          <h2 id="directory-heading">All sites</h2>
        </div>
      </header>
      <.section_unavailable retry={@retry}>
        The sites could not be loaded just now.
      </.section_unavailable>
    </section>
    """
  end

  def render(assigns) do
    ~H"""
    <section id="site-directory" class="pb-site-directory" aria-labelledby="directory-heading">
      <header class="pb-directory-intro">
        <div>
          <h2 id="directory-heading">All sites</h2>
        </div>
        <span class="pb-directory-total">
          {metric(@page.total)} {if @page.total == 1, do: "site", else: "sites"}
        </span>
      </header>

      <form
        id="directory-search-form"
        action={~p"/patchbay/sites"}
        method="get"
        class="pb-directory-search"
        role="search"
        phx-hook=".DirectorySearch"
      >
        <label class="pb-directory-search-field">
          <span class="visually-hidden">Search sites</span>
          <input type="search" name="q" value={@page.q} maxlength="100" placeholder="Search websites" />
        </label>
        <label class="pb-directory-select">
          <span class="visually-hidden">Category</span>
          <select name="category">
            <option value="">All categories</option>
            <option
              :for={category <- SiteDirectory.categories()}
              value={category}
              selected={@page.category == category}
            >
              {category}
            </option>
          </select>
        </label>
        <button class="rg-button rg-button--secondary" type="submit">Search</button>
      </form>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".DirectorySearch">
        export default {
          mounted() {
            this.select = this.el.querySelector("select[name='category']")
            this.onChange = () => this.el.requestSubmit()
            this.select?.addEventListener("change", this.onChange)
          },
          destroyed() {
            this.select?.removeEventListener("change", this.onChange)
          }
        }
      </script>
      <div :if={@page.q != ""} class="pb-directory-results-heading">
        <p role="status">
          <span>Results for “{@page.q}”</span>
        </p>
        <p>{length(@page.sites)} / {metric(@page.total)}</p>
      </div>

      <div
        :if={@page.sites != []}
        class="pb-directory-scroll"
        role="region"
        aria-label="Website listings"
      >
        <table id="directory-table" class="pb-directory-table">
          <caption id="directory-caption" class="visually-hidden">
            WebMCP websites, tool counts and public forum posts
          </caption>
          <thead id="directory-columns">
            <tr>
              <th scope="col">Website</th>
              <th scope="col" class="pb-directory-numeric">Tools</th>
              <th scope="col" class="pb-directory-numeric">Posts</th>
            </tr>
          </thead>
          <tbody
            id="directory-rows"
            phx-update="stream"
            phx-hook="MotionArrivals"
            phx-viewport-bottom={if @page.page < @page.pages, do: "load-more"}
          >
            <tr :for={{dom_id, site} <- @streams.sites} id={dom_id} class="pb-directory-row">
              <th scope="row">
                <div class="pb-directory-identity">
                  <button
                    type="button"
                    class="pb-directory-expand"
                    phx-click="toggle"
                    phx-value-host={site.host}
                    aria-expanded={to_string(MapSet.member?(@expanded, site.host))}
                    aria-controls={"tools-" <> site.host}
                  >
                    <span class="pb-directory-mark" aria-hidden="true">
                      <img
                        :if={site.logo_path}
                        src={picture_url(site.logo_path)}
                        alt=""
                        width="28"
                        height="28"
                        loading="lazy"
                      />
                      <span :if={!site.logo_path}>{initial(site.name)}</span>
                    </span>
                    <span class="pb-directory-name">{site.name}</span>
                  </button>
                  <div class="pb-directory-url">
                    <.web_link href={site.page_url} rel="noopener noreferrer" target="_blank">{site.host}<span class="visually-hidden"> (opens website)</span></.web_link>
                  </div>
                  <a class="pb-directory-forum" href={domain_path(site.domain)}>
                    <span>View Forum</span><span class="visually-hidden"> for {site.name}</span>
                  </a>
                </div>
                <div
                  id={"tools-" <> site.host}
                  class="pb-directory-detail-inner"
                  hidden={!MapSet.member?(@expanded, site.host)}
                >
                  <img
                    :if={site.screenshot_path}
                    class="pb-directory-picture"
                    src={picture_url(site.screenshot_path)}
                    alt={site.name <> " home page"}
                    width="1600"
                    height="1000"
                    loading="lazy"
                    decoding="async"
                  />
                  <ul
                    :if={site.tools != []}
                    class="pb-directory-tool-list"
                    tabindex="0"
                    aria-label={"WebMCP tools on " <> site.name}
                  >
                    <li :for={tool <- site.tools}><code>{tool["name"]}</code></li>
                  </ul>
                  <p :if={is_nil(site.tool_count)} class="pb-directory-empty">Not checked yet.</p>
                  <p :if={site.tool_count == 0} class="pb-directory-empty">No WebMCP tools found.</p>
                </div>
              </th>
              <td class="pb-directory-numeric">
                <button
                  type="button"
                  class="pb-directory-count"
                  phx-click="toggle"
                  phx-value-host={site.host}
                  aria-label={"View tools for " <> site.name}
                  aria-expanded={to_string(MapSet.member?(@expanded, site.host))}
                  aria-controls={"tools-" <> site.host}
                >
                  <strong :if={site.tool_count}>{site.tool_count}</strong>
                  <span :if={!site.tool_count} class="pb-directory-unchecked">Not checked</span>
                </button>
              </td>
              <td class="pb-directory-numeric">
                <a
                  href={domain_path(site.domain)}
                  class="pb-directory-posts"
                  aria-label={"Public posts for " <> site.domain}
                >
                  {metric(site.forum_posts)}
                </a>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <Regent.Primitives.empty_state
        :if={@page.sites == [] and @page.q == "" and @page.category in [nil, ""]}
        title="No sites"
      >
        <:action>
          <a class="rg-button rg-button--secondary" href={~p"/patchbay"}>
            <span class="rg-button__label">Ask a question</span>
          </a>
        </:action>
      </Regent.Primitives.empty_state>
      <Regent.Primitives.empty_state
        :if={@page.sites == [] and (@page.q != "" or @page.category not in [nil, ""])}
        title="No matches"
      >
        <p :if={@page.q != ""}>
          No listed WebMCP site matched “{@page.q}”. You can search forum discussions or view all listed sites.
        </p>
        <:action>
          <a
            :if={@page.q != ""}
            class="rg-button rg-button--primary"
            href={~p"/patchbay/forum?#{[q: @page.q]}"}
          >
            <span class="rg-button__label">Search forum for “{@page.q}”</span>
          </a>
          <a class="rg-button rg-button--secondary" href={~p"/patchbay/sites"}>
            <span class="rg-button__label">All sites</span>
          </a>
        </:action>
      </Regent.Primitives.empty_state>
      <div class="pb-directory-pagination">
        <button
          :if={@page.page < @page.pages}
          type="button"
          phx-click="load-more"
          phx-disable-with="Loading…"
          class="rg-button rg-button--secondary"
        >Load more sites</button>
        <p :if={@more_failed} role="alert">More sites could not be loaded just now.</p>
        <p :if={@page.page == @page.pages and @page.total > 0} role="status">
          End of results
        </p>
        <noscript :if={@page.page < @page.pages}>
          <a href={SiteDirectory.page_url(@page, @page.page + 1)}>Next sites →</a>
        </noscript>
      </div>
      <p class="pb-directory-method">
        <a href={~p"/patchbay/docs" <> "#directory"}>Sources</a>
        <span aria-hidden="true">·</span>
        <a href={~p"/patchbay/webmcp"}>WebMCP guide</a>
      </p>
    </section>
    """
  end

  defp subscribe_sites(socket, sites) do
    domains = MapSet.new(sites, & &1.domain)

    if connected?(socket) do
      domains
      |> MapSet.difference(socket.assigns.subscribed)
      |> Enum.each(&(:ok = Phoenix.PubSub.subscribe(Regents.PubSub, SiteCheck.topic(&1))))
    end

    assign(socket, subscribed: MapSet.union(socket.assigns.subscribed, domains))
  end

  defp initial(name), do: name |> String.first() |> String.upcase()
  defp metric(nil), do: "—"
  defp metric(number), do: to_string(number)
end
