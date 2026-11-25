defmodule RegentsWeb.Components.AppSidebar do
  @moduledoc false

  use Phoenix.Component

  @regents_paths ~w(/app /account /stake /redeem)
  @autolaunch_paths ~w(/autolaunch/app /autolaunch/auctions /autolaunch/tokens
    /autolaunch/portfolio /autolaunch/create /autolaunch/earn /autolaunch/agent-business
    /autolaunch/stock /autolaunch/convert /autolaunch/stocks)
  @patchbay_paths ~w(/patchbay/app /patchbay/forum /patchbay/posts /patchbay/sites
    /patchbay/validate /patchbay/fixes /patchbay/incidents /patchbay/wallet-bench /patchbay/offers)
  @techtree_paths ~w(/techtree/app /techtree/results /techtree/wallet-bench /techtree/train
    /techtree/climbs /techtree/account/projects)

  def workspace?(path) when is_binary(path) do
    Enum.any?(
      @regents_paths ++
        @autolaunch_paths ++
        @patchbay_paths ++
        @techtree_paths ++
        ~w(/keyfleet/app /keyfleet/classic /keyfleet/syndicate /keyfleet/cascade
          /keyfleet/accelerant /keyfleet/fleets),
      &under?(path, &1)
    )
  end

  def workspace?(_path), do: false

  attr(:path, :string, required: true)
  attr(:product, :string, required: true)
  slot(:controls, required: true)

  def bar(assigns) do
    assigns = assign(assigns, :groups, groups())

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
        <p class="workspace-sidebar__heading">Products</p>
        <details
          :for={{product, label, icon, links} <- @groups}
          id={"workspace-product-#{product}"}
          class="workspace-product"
          open={product == @product and !under?(@path, "/account")}
          data-active={product == @product and !under?(@path, "/account")}
        >
          <summary aria-label={label} title={label}>
            <Regent.Icons.icon name={icon} />
            <span class="workspace-sidebar__label">{label}</span>
            <Regent.Icons.icon name="chevron-down" class="workspace-product__chevron" />
          </summary>
          <ul class="workspace-product__links">
            <% current = current_link(links, @path) %>
            <li :for={{text, href} <- links}>
              <a href={href} aria-current={if(href == current, do: current_state(href, @path))}>
                {text}
              </a>
            </li>
          </ul>
        </details>
      </nav>
      <button
        type="button"
        class="workspace-scrim"
        data-workspace-scrim
        tabindex="-1"
        aria-label="Close products"
      >
      </button>
      <div class="workspace-bar__controls">{render_slot(@controls)}</div>
    </div>
    """
  end

  defp groups do
    [
      {"regents", "Regents", "layout-dashboard",
       [{"Overview", "/app"}, {"Stake", "/stake"}, {"Redeem", "/redeem"}]},
      {"autolaunch", "Autolaunch", "rocket",
       [
         {"Explore", "/autolaunch/app"},
         {"Auctions", "/autolaunch/auctions"},
         {"Tokens", "/autolaunch/tokens"},
         {"Stocks", "/autolaunch/stocks"},
         {"Portfolio", "/autolaunch/portfolio"},
         {"Create", "/autolaunch/create"}
       ] ++ earn_links()},
      {"keyfleet", "Keyfleet", "key-round",
       [
         {"Fleets", "/keyfleet/app"},
         {"Classic #1", "/keyfleet/classic/1"},
         {"Workspace", "/keyfleet/classic/1/workspace"},
         {"Proposals", "/keyfleet/classic/1/proposals"},
         {"Treasury", "/keyfleet/classic/1/treasury"}
       ]},
      {"patchbay", "Patchbay", "life-buoy",
       [
         {"Terminal", "/patchbay/app"},
         {"Security", "/patchbay/incidents"},
         {"Validate", "/patchbay/validate"},
         {"Threads", "/patchbay/forum"},
         {"Ask", "/patchbay/forum?ask=1#pb-hero"},
         {"Sites", "/patchbay/sites"},
         {"Wallet Bench", "/patchbay/wallet-bench"}
       ] ++ offer_links()},
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
