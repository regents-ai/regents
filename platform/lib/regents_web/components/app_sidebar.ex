defmodule RegentsWeb.Components.AppSidebar do
  @moduledoc false

  use Phoenix.Component

  alias RegentsWeb.RouteCatalog

  @regents_paths ~w(/app /account /stake /redeem /pair /regents /docs /agents /start /admin)
  @autolaunch_paths ~w(/autolaunch/app /autolaunch/auctions /autolaunch/tokens
    /autolaunch/portfolio /autolaunch/create /autolaunch/earn /autolaunch/agent-business
    /autolaunch/stock /autolaunch/convert /autolaunch/stocks /autolaunch/upcoming
    /autolaunch/regent /autolaunch/docs /autolaunch/agents /autolaunch/how-it-works)
  @techtree_paths ~w(/techtree/app /techtree/results /techtree/wallet-bench /techtree/train
    /techtree/climbs /techtree/account/projects /techtree/docs /techtree/agents
    /techtree/formal /techtree/examples /techtree/watchdog)
  @keyfleet_paths ~w(/keyfleet/app /keyfleet/classic /keyfleet/syndicate /keyfleet/cascade
    /keyfleet/accelerant /keyfleet/fleets /keyfleet/docs /keyfleet/agents)
  @patchbay_public ~w(about blog changelog privacy terms)

  def workspace?("/patchbay/" <> rest) do
    hd(String.split(rest, "/", parts: 2)) not in @patchbay_public
  end

  def workspace?(path) when is_binary(path) do
    Enum.any?(
      @regents_paths ++ @autolaunch_paths ++ @techtree_paths ++ @keyfleet_paths,
      &under?(path, &1)
    )
  end

  def workspace?(_path), do: false

  attr(:path, :string, required: true)
  attr(:product, :string, required: true)
  attr(:section_path, :string, default: nil)
  attr(:extra_links, :list, default: [])
  attr(:guides, :map, default: nil)
  slot(:controls, required: true)

  def bar(assigns) do
    account? = under?(assigns.path, "/account")
    product = if assigns.product == "protocol", do: "regents", else: assigns.product

    {current, other} =
      Enum.split_with(groups(), fn {slug, _, _, _} ->
        !account? and !assigns.guides and slug == product
      end)

    assigns =
      assign(assigns,
        account?: account?,
        current_groups: current,
        other_groups: other,
        account_tabs: Enum.reject(RouteCatalog.account_tabs(), &(&1.path == "/account"))
      )

    ~H"""
    <div
      id="workspace-bar"
      class="workspace-bar"
      phx-mounted={Phoenix.LiveView.JS.ignore_attributes(["data-collapsed", "data-mobile-open"])}
    >
      <a class="workspace-bar__account" href="/account" aria-current={@path == "/account" && "page"}>
        <Regent.Icons.icon name="user-round" /> Account
      </a>
      <button
        type="button"
        class="workspace-toggle"
        aria-controls="workspace-sidebar"
        aria-expanded="true"
        aria-label="Collapse sidebar"
        id="workspace-sidebar-toggle"
        phx-mounted={Phoenix.LiveView.JS.ignore_attributes(["aria-expanded", "aria-label"])}
        data-workspace-toggle
      >
        <span class="workspace-toggle__line"></span>
        <Regent.Icons.icon name="chevron-left" class="workspace-toggle__collapse" />
        <Regent.Icons.icon name="chevron-right" class="workspace-toggle__expand" />
        <Regent.Icons.icon name="menu" class="workspace-toggle__menu" />
        <span class="workspace-toggle__tip" aria-hidden="true">
          <span class="workspace-toggle__collapse">Collapse</span>
          <span class="workspace-toggle__expand">Expand</span>
        </span>
      </button>
      <nav id="workspace-sidebar" class="workspace-sidebar" aria-label="Workspace">
        <a class="workspace-sidebar__brand" href="/app" aria-label="Regents Labs" title="Regents Labs">
          <span class="workspace-sidebar__crown" aria-hidden="true"></span>
          <span class="workspace-sidebar__label">Regents Labs</span>
        </a>
        <div class="workspace-account">
          <a
            class="workspace-sidebar__account"
            href="/account"
            aria-label="Account"
            title="Account"
            aria-current={@path == "/account" && "page"}
          >
            <Regent.Icons.icon name="user-round" />
            <span class="workspace-sidebar__label">Account</span>
          </a>
          <details class="workspace-account__sections" open={@account?}>
            <summary aria-label="Account sections" title="Account sections">
              <Regent.Icons.icon name="chevron-down" class="workspace-product__chevron" />
            </summary>
            <ul class="workspace-product__links">
              <li :for={tab <- @account_tabs}>
                <.link :if={@account?} patch={tab.path} aria-current={@path == tab.path && "page"}>
                  {tab.label}
                </.link>
                <a :if={!@account?} href={tab.path}>{tab.label}</a>
              </li>
            </ul>
          </details>
        </div>
        <.guide_navigation :if={@guides} guides={@guides} path={@path} />
        <.product_group
          :for={{product, label, icon, links} <- @current_groups}
          product={product}
          label={label}
          icon={icon}
          links={links ++ @extra_links}
          path={@path}
          section_path={@section_path}
          current
        />
        <p class="workspace-sidebar__heading">Products</p>
        <.product_group
          :for={{product, label, icon, links} <- @other_groups}
          product={product}
          label={label}
          icon={icon}
          links={links}
          path={if(@guides, do: "", else: @path)}
        />
      </nav>
      <button
        type="button"
        class="workspace-scrim"
        data-workspace-scrim
        tabindex="-1"
        aria-label="Close products"
      ></button>
      <div class="workspace-bar__controls">{render_slot(@controls)}</div>
    </div>
    """
  end

  attr(:guides, :map, required: true)
  attr(:path, :string, required: true)

  defp guide_navigation(assigns) do
    ~H"""
    <details id="workspace-guides" class="workspace-product workspace-product--current" open>
      <summary aria-label={@guides.title} title={@guides.title}>
        <Regent.Icons.icon name="book-open" />
        <span class="workspace-sidebar__label">{@guides.title}</span>
        <Regent.Icons.icon name="chevron-down" class="workspace-product__chevron" />
      </summary>
      <div class="workspace-product__links">
        <a href="/docs" aria-current={@path == "/docs" && "page"}>All docs</a>
        <details
          :for={{label, links} <- @guides.groups}
          class="workspace-guide-group"
          open={@path == "/docs" or Enum.any?(links, fn {_, path} -> path == @path end)}
        >
          <summary>{label}</summary>
          <ul>
            <li :for={{text, href} <- links}>
              <a href={href} aria-current={href == @path && "page"}>{text}</a>
            </li>
          </ul>
        </details>
      </div>
    </details>
    """
  end

  attr(:product, :string, required: true)
  attr(:label, :string, required: true)
  attr(:icon, :string, required: true)
  attr(:links, :list, required: true)
  attr(:path, :string, required: true)
  attr(:section_path, :string, default: nil)
  attr(:current, :boolean, default: false)

  defp product_group(assigns) do
    assigns =
      assign(
        assigns,
        :selected,
        current_link(assigns.links, assigns.path) || assigns.section_path
      )

    ~H"""
    <details
      id={"workspace-product-#{@product}"}
      class={["workspace-product", @current && "workspace-product--current"]}
      open={@current}
      data-active={@current}
    >
      <summary aria-label={@label} title={@label}>
        <Regent.Icons.icon name={@icon} />
        <span class="workspace-sidebar__label">{@label}</span>
        <Regent.Icons.icon name="chevron-down" class="workspace-product__chevron" />
      </summary>
      <ul class="workspace-product__links">
        <li :for={{label, href} <- @links}>
          <a href={href} aria-current={if(href == @selected, do: current_state(href, @path))}>
            {label}
          </a>
        </li>
      </ul>
    </details>
    """
  end

  defp groups do
    [
      {"regents", "Regents", "layout-dashboard",
       [{"Overview", "/app"}, {"Stake", "/stake"}, {"Redeem", "/redeem"}, {"Docs", "/docs"}]},
      {"autolaunch", "Autolaunch", "rocket",
       [
         {"Explore", "/autolaunch/app"},
         {"Auctions", "/autolaunch/auctions"},
         {"Tokens", "/autolaunch/tokens"},
         {"Stocks", "/autolaunch/stocks"},
         {"Portfolio", "/autolaunch/portfolio"},
         {"Create", "/autolaunch/create"},
         {"Docs", "/docs/autolaunch"}
       ] ++ earn_links()},
      {"keyfleet", "Keyfleet", "key-round",
       [
         {"Fleets", "/keyfleet/app"},
         {"Classic #1", "/keyfleet/classic/1"},
         {"Workspace", "/keyfleet/classic/1/workspace"},
         {"Proposals", "/keyfleet/classic/1/proposals"},
         {"Treasury", "/keyfleet/classic/1/treasury"},
         {"Docs", "/docs/keyfleet"}
       ]},
      {"patchbay", "Patchbay", "life-buoy",
       [
         {"App", "/patchbay/app"},
         {"Security", "/patchbay/incidents"},
         {"Validate", "/patchbay/validate"},
         {"Wallet Bench", "/patchbay/wallet-bench"},
         {"Threads", "/patchbay/forum"},
         {"Sites", "/patchbay/sites"},
         {"Docs", "/docs/patchbay"}
       ] ++ offer_links() ++ [{"Ask", "/patchbay/forum?ask=1#pb-hero"}]},
      {"techtree", "Techtree", "flask-conical",
       [
         {"Overview", "/techtree/app"},
         {"Results", "/techtree/results"},
         {"Projects", "/techtree/account/projects"},
         {"Wallet Bench", "/techtree/wallet-bench"},
         {"Docs", "/techtree/docs"}
       ]},
      {"cloak", "Cloak", "shield",
       [{"Overview", "/cloak"}, {"Install", "/cloak/install"}, {"Docs", "/docs/cloak"}]}
    ]
  end

  defp earn_links do
    if Regents.Autolaunch.Earn.Catalog.enabled?(), do: [{"Earn", "/autolaunch/earn"}], else: []
  end

  defp offer_links do
    if Regents.Patchbay.Offers.enabled?(), do: [{"Offers", "/patchbay/offers"}], else: []
  end

  defp current_link(links, path) do
    links
    |> Enum.map(&elem(&1, 1))
    |> Enum.filter(&under?(path, &1))
    |> Enum.max_by(&byte_size/1, fn -> nil end)
  end

  defp current_state(path, path), do: "page"
  defp current_state(_href, _path), do: "location"

  defp under?(path, root), do: path == root or String.starts_with?(path, root <> "/")
end
