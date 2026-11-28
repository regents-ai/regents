defmodule RegentsWeb.RouteCatalog do
  @moduledoc "Canonical behavior metadata for the founder-approved route allowlist."

  alias RegentsWeb.NotFoundError

  alias __MODULE__.{
    Entry,
    PageTarget,
    RouteTarget,
    SidebarHeading,
    SidebarModel,
    Spec,
    ViewerProfileTarget
  }

  @slug ~r/\A[a-z0-9][a-z0-9-]{0,62}\z/

  @entries [
    %Entry{
      path_pattern: "/",
      live_action: :home,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :home
    },
    %Entry{
      path_pattern: "/app",
      live_action: :app,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :app
    },
    %Entry{
      path_pattern: "/articles",
      live_action: :blog,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :blog
    },
    %Entry{
      path_pattern: "/articles/:slug",
      live_action: :blog_post,
      parameter_schema: %{slug: :slug},
      reserved_values: %{},
      route_spec_id: :blog_post
    },
    %Entry{
      path_pattern: "/start",
      live_action: :agent_start,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :agent_start
    },
    %Entry{
      path_pattern: "/paper-pro-daily",
      live_action: :paper_pro_daily,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :paper_pro_daily
    },
    %Entry{
      path_pattern: "/paper-pro-daily/:paper",
      live_action: :paper_pro_daily_paper,
      parameter_schema: %{paper: :paper_anchor},
      reserved_values: %{},
      route_spec_id: :paper_pro_daily
    },
    %Entry{
      path_pattern: "/literature",
      live_action: :literature,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :literature
    },
    %Entry{
      path_pattern: "/about",
      live_action: :about,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :about
    },
    %Entry{
      path_pattern: "/contact",
      live_action: :contact,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :contact
    },
    %Entry{
      path_pattern: "/docs",
      live_action: :docs,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :docs
    },
    %Entry{
      path_pattern: "/docs/:page",
      live_action: :docs_page,
      parameter_schema: %{page: :docs_page},
      reserved_values: %{},
      route_spec_id: :docs
    },
    %Entry{
      path_pattern: "/docs/:product/:page",
      live_action: :docs_subpage,
      parameter_schema: %{product: :docs_product, page: :docs_subpage},
      reserved_values: %{},
      route_spec_id: :docs
    },
    %Entry{
      path_pattern: "/account",
      live_action: :account,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :account
    },
    %Entry{
      path_pattern: "/account/agents",
      live_action: :account_agents,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :account_agents
    },
    %Entry{
      path_pattern: "/account/points",
      live_action: :points,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :points
    },
    %Entry{
      path_pattern: "/account/wallets",
      live_action: :wallets,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :wallets
    },
    %Entry{
      path_pattern: "/account/connections",
      live_action: :connections,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :connections
    },
    %Entry{
      path_pattern: "/account/names",
      live_action: :names,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :names
    },
    %Entry{
      path_pattern: "/pair",
      live_action: :pair,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :pair
    },
    %Entry{
      path_pattern: "/regents/:slug",
      live_action: :regent_profile,
      parameter_schema: %{slug: :slug},
      reserved_values: %{},
      route_spec_id: :regent_profile
    },
    %Entry{
      path_pattern: "/stake",
      live_action: :stake,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :stake
    },
    %Entry{
      path_pattern: "/redeem",
      live_action: :redeem,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :redeem
    },
    %Entry{
      path_pattern: "/redeem/gallery",
      live_action: :redeem_gallery,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :redeem_gallery
    },
    %Entry{
      path_pattern: "/cloak",
      live_action: :cloak,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :cloak
    },
    %Entry{
      path_pattern: "/cloak/install",
      live_action: :cloak_install,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :cloak_install
    },
    %Entry{
      path_pattern: "/siwa",
      live_action: :siwa,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :siwa
    },
    %Entry{
      path_pattern: "/admin/articles",
      live_action: :articles_admin,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :articles_admin
    }
  ]

  @specs %{
    articles_admin:
      {:articles_admin, :regent_ops, "Regents Labs", "New Article", "/articles",
       [:profile_actions], :regents_labs, %{}},
    blog:
      {:blog, :regent_ops, "Regents Labs", "Articles", "/articles", [:profile_actions],
       :regents_labs, %{}},
    blog_post:
      {:blog_post, :regent_ops, "Regents Labs", "Articles", "/articles", [:profile_actions],
       :regents_labs, %{}},
    agent_start:
      {:agent_start, :regent_ops, "Regents Labs", "Connect your agent", "/app",
       [:profile_actions], :regents_labs, %{}},
    home: {:home, nil, nil, "Regent", "/", [], :home, %{}},
    paper_pro_daily:
      {:paper_pro_daily, :regent_ops, "Regents Labs", "Paper Pro Daily", "/paper-pro-daily", [],
       :regents_labs, %{}},
    literature:
      {:literature, :regent_ops, "Regents Labs", "AI & SCIFI", "/literature", [], :regents_labs,
       %{}},
    about: {:about, :regent_ops, "Regents Labs", "About", "/about", [], :regents_labs, %{}},
    contact:
      {:contact, :regent_ops, "Regents Labs", "Contact", "/contact", [], :regents_labs, %{}},
    docs: {:docs, :regent_ops, "Regents Labs", "Docs", "/docs", [], :regents_labs, %{}},
    app:
      {:app, :regent_ops, "Regents Labs", "Overview", "/app",
       [:wallet_status, :network_status, :profile_actions], :regents_labs, %{}},
    account:
      {:account, :regent_ops, "Regents Labs", "Account", "/app", [:profile_actions],
       :regents_labs, %{}},
    account_agents:
      {:account_agents, :regent_ops, "Regents Labs", "Agents", "/app", [:profile_actions],
       :regents_labs, %{}},
    pair:
      {:pair, :regent_ops, "Regents Labs", "Pair New Agent", "/app", [:profile_actions],
       :regents_labs, %{}},
    points:
      {:points, :regent_ops, "Regents Labs", "Points", "/app", [:profile_actions], :regents_labs,
       %{}},
    wallets:
      {:wallets, :regent_ops, "Regents Labs", "Wallets", "/app", [:profile_actions],
       :regents_labs, %{}},
    connections:
      {:connections, :regent_ops, "Regents Labs", "Connections", "/app", [:profile_actions],
       :regents_labs, %{}},
    names:
      {:names, :regent_ops, "Regents Labs", "Names", "/app", [:profile_actions], :regents_labs,
       %{}},
    regent_profile:
      {:regent_profile, :regent_ops, "Regents Labs", "Regent Profile", "/app",
       [:wallet_status, :network_status, :profile_actions], :regent_record, %{}},
    stake:
      {:stake, :regent_ops, "Regents Labs", "Stake", "/app",
       [:wallet_status, :network_status, :profile_actions], :regents_labs, %{}},
    redeem:
      {:redeem, :regent_ops, "Regents Labs", "Redeem", "/app",
       [:wallet_status, :network_status, :profile_actions], :regents_labs, %{}},
    redeem_gallery:
      {:redeem_gallery, :regent_ops, "Regents Labs", "Regents Club passes", "/app",
       [:profile_actions], :regents_labs, %{}},
    cloak:
      {:cloak, :regent_ops, "Regents Labs", "Cloak", "/app", [:profile_actions], :regents_labs,
       %{}},
    cloak_install:
      {:cloak_install, :regent_ops, "Regents Labs", "Install", "/app", [:profile_actions],
       :regents_labs, %{}},
    siwa: {:siwa, :regent_ops, "Regents Labs", "SIWA", "/app", [], :regents_labs, %{}}
  }

  # The product each page belongs to (`Regent.Site.products/0`): Regents, unless named
  # here. A product's overview page belongs to that product. The root layout marks the
  # page with it, and a sidebar link to another product's page loads that page in full.
  @products %{
    stake: "protocol",
    cloak: "cloak",
    cloak_install: "cloak",
    siwa: "siwa"
  }

  # The products with a side menu of their own: the app's pages and the reading, on
  # Regents' pages and on Protocol's (Stake is one of the app's pages). Every other
  # product's page here is its only one, so it carries none. No side menu lists the
  # products: the bar's product menu is the one way between them.
  @app_menu_products ~w(regents protocol)

  # The Account pages are tabs of one another.
  @account_tabs [
    %RouteTarget{route_id: :account, label: "Account", path: "/account"},
    %RouteTarget{route_id: :account_agents, label: "Agents", path: "/account/agents"},
    %RouteTarget{route_id: :points, label: "Points", path: "/account/points"},
    %RouteTarget{route_id: :wallets, label: "Wallets", path: "/account/wallets"},
    %RouteTarget{route_id: :connections, label: "Connections", path: "/account/connections"},
    %RouteTarget{route_id: :names, label: "Names", path: "/account/names"}
  ]
  @tabs Map.new(@account_tabs, &{&1.route_id, @account_tabs})

  @doc "The sections available in the Account navigation."
  def account_tabs, do: @account_tabs

  def fetch!(action, params \\ %{}) do
    entry = Enum.find(@entries, &(&1.live_action == action)) || raise(NotFoundError)
    validate_params!(entry, params)
    build_spec(entry.route_spec_id, params)
  end

  @doc "The product of the page a sidebar entry or route id names."
  def product(route_id), do: Map.get(@products, route_id, "regents")

  def design_handoff do
    json =
      %{"schema_version" => 1, "routes" => Enum.map(@entries, &handoff_route/1)}
      |> ordered_json_value()
      |> Jason.encode!()

    %{json: json, digest: Base.encode16(:crypto.hash(:sha256, json), case: :lower)}
  end

  defp validate_params!(
         %Entry{live_action: :docs_subpage},
         %{"product" => product, "page" => page}
       )
       when is_binary(product) and is_binary(page) do
    if RegentsWeb.Docs.Pages.page("/docs/" <> product <> "/" <> page) != nil,
      do: :ok,
      else: raise(NotFoundError)
  end

  defp validate_params!(%Entry{live_action: :docs_subpage}, _params), do: raise(NotFoundError)

  defp validate_params!(%Entry{parameter_schema: schema, reserved_values: reserved}, params) do
    valid? =
      Enum.all?(schema, fn {key, type} ->
        value = Map.get(params, Atom.to_string(key))
        valid_parameter?(type, value) and value not in Map.get(reserved, key, [])
      end)

    if valid?, do: :ok, else: raise(NotFoundError)
  end

  defp valid_parameter?(:slug, value), do: is_binary(value) and Regex.match?(@slug, value)

  defp valid_parameter?(:paper_anchor, value),
    do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{8}\z/, value)

  defp valid_parameter?(:docs_page, value),
    do: is_binary(value) and RegentsWeb.Docs.Pages.page("/docs/" <> value) != nil

  defp build_spec(action, params) do
    {route_id, app_id, app_label, page_label, root, controls, background, local_state} =
      Map.fetch!(@specs, action)

    product = product(route_id)

    %Spec{
      route_id: route_id,
      product: product,
      destination: destination(action, params),
      app_id: app_id,
      app_display_label: app_label,
      page_display_label: page_label,
      canonical_root: root,
      sidebar_model: sidebar_model(app_id, product, route_id),
      tabs: Map.get(@tabs, route_id, []),
      header_controls: controls,
      background_slot: background,
      scroll_policy: :top,
      local_state: local_state
    }
  end

  defp sidebar_model(nil, _product, _route_id), do: %SidebarModel{id: :public, targets: []}

  defp sidebar_model(:regent_ops, _product, :docs),
    do: %SidebarModel{id: :none, targets: []}

  defp sidebar_model(:regent_ops, product, _route_id) when product not in @app_menu_products,
    do: %SidebarModel{id: :none, targets: []}

  defp sidebar_model(:regent_ops, _product, _route_id) do
    %SidebarModel{
      id: :regent_ops,
      targets: [
        %RouteTarget{route_id: :app, label: "Overview", path: "/app"},
        %RouteTarget{route_id: :stake, label: "Stake", path: "/stake"},
        %RouteTarget{route_id: :redeem, label: "Redeem", path: "/redeem"},
        %RouteTarget{route_id: :account, label: "Account", path: "/account"},
        %ViewerProfileTarget{label: "Profile"},
        %SidebarHeading{label: "Reading"},
        %PageTarget{
          route_id: :paper_pro_daily,
          label: "Daily Research",
          path: "/paper-pro-daily"
        },
        %PageTarget{route_id: :docs, label: "Docs", path: "/docs"},
        %PageTarget{route_id: :about, label: "About", path: "/about"},
        %PageTarget{route_id: :literature, label: "AI & SCIFI", path: "/literature"}
      ]
    }
  end

  defp handoff_route(entry) do
    spec = fetch!(entry.live_action, handoff_params(entry.live_action))

    %{
      "app_display_label" => spec.app_display_label,
      "app_id" => spec.app_id,
      "background_slot" => spec.background_slot,
      "canonical_root" => spec.canonical_root,
      "destination" => spec.destination,
      "header_controls" => spec.header_controls,
      "live_action" => entry.live_action,
      "local_state" => spec.local_state,
      "page_display_label" => spec.page_display_label,
      "parameter_schema" => entry.parameter_schema,
      "path_pattern" => entry.path_pattern,
      "product" => spec.product,
      "reserved_values" => entry.reserved_values,
      "route_id" => spec.route_id,
      "scroll_policy" => spec.scroll_policy,
      "sidebar_model" => sidebar_handoff(spec.sidebar_model),
      "tabs" => Enum.map(spec.tabs, &sidebar_target_handoff/1)
    }
  end

  defp sidebar_handoff(sidebar) do
    %{"id" => sidebar.id, "targets" => Enum.map(sidebar.targets, &sidebar_target_handoff/1)}
  end

  defp sidebar_target_handoff(%RouteTarget{} = target) do
    %{
      "type" => "route",
      "route_id" => target.route_id,
      "label" => target.label,
      "destination" => target.path
    }
  end

  defp sidebar_target_handoff(%PageTarget{} = target) do
    %{
      "type" => "page",
      "route_id" => target.route_id,
      "label" => target.label,
      "destination" => target.path
    }
  end

  defp sidebar_target_handoff(%ViewerProfileTarget{} = target) do
    %{
      "type" => "viewer_profile",
      "label" => target.label,
      "destination" => "/regents/:viewer_slug"
    }
  end

  defp sidebar_target_handoff(%SidebarHeading{} = heading) do
    %{"type" => "heading", "label" => heading.label}
  end

  defp handoff_params(:regent_profile), do: %{"slug" => "regent"}
  defp handoff_params(:blog_post), do: %{"slug" => "example-post"}
  defp handoff_params(:paper_pro_daily_paper), do: %{"paper" => "00000000"}
  defp handoff_params(:docs_page), do: %{"page" => "limits"}
  defp handoff_params(:docs_subpage), do: %{"product" => "cloak", "page" => "install"}
  defp handoff_params(_), do: %{}

  defp destination(:regent_profile, %{"slug" => slug}), do: "/regents/#{slug}"
  defp destination(:blog_post, %{"slug" => slug}), do: "/articles/#{slug}"
  defp destination(:paper_pro_daily, %{"paper" => paper}), do: "/paper-pro-daily/#{paper}"
  defp destination(:docs, %{"product" => product, "page" => page}), do: "/docs/#{product}/#{page}"
  defp destination(:docs, %{"page" => page}), do: "/docs/#{page}"

  defp destination(action, _params) do
    @entries
    |> Enum.find(&(&1.live_action == action))
    |> Map.fetch!(:path_pattern)
  end

  defp ordered_json_value(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested_value} ->
      {to_string(key), ordered_json_value(nested_value)}
    end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Jason.OrderedObject.new()
  end

  defp ordered_json_value(value) when is_list(value), do: Enum.map(value, &ordered_json_value/1)
  defp ordered_json_value(value), do: value
end
