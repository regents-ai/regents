defmodule AshPlatformWeb.Components.ShellRenderTest do
  use AshPlatformWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias AshPlatform.AccessContext.AccountControl
  alias AshPlatformWeb.Components.Shell
  alias AshPlatformWeb.RouteCatalog

  test "renders one current-app selector with the four canonical application roots" do
    html = render_shell(RouteCatalog.fetch!(:techtree))
    document = LazyHTML.from_fragment(html)

    assert document |> LazyHTML.query("#app-selector > summary") |> LazyHTML.text() =~ "Techtree"

    refute Enum.empty?(
             LazyHTML.query(
               document,
               "#app-selector > summary img[src='/images/brand/regents-crown-flat-dark.svg']"
             )
           )

    links = LazyHTML.query(document, "#app-selector-menu a")

    assert Enum.map(links, &LazyHTML.text/1) |> Enum.map(&String.trim/1) == [
             "Formation",
             "Autolaunch",
             "Techtree",
             "Regents Labs"
           ]

    assert LazyHTML.attribute(links, "href") == [
             "/formation",
             "/autolaunch",
             "/techtree",
             "/app"
           ]

    refute Enum.empty?(
             LazyHTML.query(
               document,
               "#app-selector-menu a[aria-current='page'][href='/techtree']"
             )
           )

    refute html =~ "Public workspace"
  end

  test "keeps anonymous account control separate and preserves the auth status seam" do
    html = render_shell(RouteCatalog.fetch!(:app))
    document = LazyHTML.from_fragment(html)

    refute Enum.empty?(
             LazyHTML.query(document, "#account-control [data-account-target='sign-in']")
           )

    assert Enum.empty?(LazyHTML.query(document, "#app-selector [data-account-target]"))

    refute Enum.empty?(
             LazyHTML.query(
               document,
               "#account-auth-status[role='status'][aria-live='polite'][aria-atomic='true'][phx-update='ignore'][hidden]"
             )
           )

    refute html =~ "data-theme-choice"
  end

  test "renders the signed-in account avatar and menu in the canonical order" do
    account = %AccountControl{
      kind: :signed_in,
      label: "0x1234…a1b2",
      profile_path: "/regents/crown",
      settings_path: "/settings",
      avatar_data_uri: "data:image/svg+xml;base64,PHN2Zy8+"
    }

    html = render_shell(RouteCatalog.fetch!(:app), account)
    document = LazyHTML.from_fragment(html)

    refute Enum.empty?(
             LazyHTML.query(document, "#account-menu summary [data-account-target='identity']")
           )

    refute Enum.empty?(LazyHTML.query(document, "#account-menu img[src^='data:image/svg+xml']"))

    labels =
      document
      |> LazyHTML.query("#account-menu [data-account-menu-item]")
      |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

    assert labels == ["Profile", "Settings", "Log Out"]
    refute html =~ "data-theme-choice"
  end

  test "omits Profile when the server has no canonical profile path" do
    account = %AccountControl{
      kind: :signed_in,
      label: "0x1234…a1b2",
      profile_path: nil,
      settings_path: "/settings"
    }

    html = render_shell(RouteCatalog.fetch!(:app), account)
    document = LazyHTML.from_fragment(html)

    assert Enum.empty?(
             LazyHTML.query(document, "#account-menu [data-account-menu-item='profile']")
           )

    assert document
           |> LazyHTML.query("#account-menu [data-account-menu-item]")
           |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim())) == ["Settings", "Log Out"]
  end

  test "preserves sidebar order, current semantics, and one internal content scroller" do
    html = render_shell(RouteCatalog.fetch!(:autolaunch_tokens))
    document = LazyHTML.from_fragment(html)

    labels =
      document
      |> LazyHTML.query("#shell-sidebar [data-sidebar-target]")
      |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

    assert labels == ["Auctions", "Tokens", "Create"]

    refute Enum.empty?(
             LazyHTML.query(
               document,
               "#shell-sidebar [aria-current='page'][href='/autolaunch/tokens']"
             )
           )

    assert Enum.count(LazyHTML.query(document, "#app-shell-scroller")) == 1
    refute Enum.empty?(LazyHTML.query(document, "#route-content[aria-busy='false']"))

    refute Enum.empty?(
             LazyHTML.query(
               document,
               "button[data-shell-menu-scrim][type='button'][aria-label='Close navigation'][hidden]"
             )
           )
  end

  test "marks only the selected Techtree presentation as current" do
    html =
      render_shell(
        RouteCatalog.fetch!(:techtree_tree, %{"tree_slug" => "genebench-pro-reference-lab"})
      )

    document = LazyHTML.from_fragment(html)

    assert Enum.count(
             LazyHTML.query(
               document,
               "[data-tree-presentation='map'][aria-current='true']"
             )
           ) == 1

    assert Enum.empty?(
             LazyHTML.query(
               document,
               "[data-tree-presentation='list'][aria-current]"
             )
           )

    assert Enum.empty?(LazyHTML.query(document, "[data-tree-presentation][aria-pressed]"))
  end

  test "renders a neutral background slot without inventing an artwork URL" do
    html = render_shell(RouteCatalog.fetch!(:formation))
    document = LazyHTML.from_fragment(html)

    refute Enum.empty?(
             LazyHTML.query(
               document,
               "#shell-background[data-background-slot='formation'][data-background-state='neutral']"
             )
           )

    refute html =~ "/images/backgrounds/"
  end

  defp render_shell(route_spec, account_control \\ anonymous_account()) do
    render_component(&Shell.shell/1,
      route_spec: route_spec,
      app_targets: RouteCatalog.app_targets(),
      account_control: account_control,
      content_status: :ready,
      presentation: :map,
      formation_panel: :overview,
      shell_instance: 1,
      content: [%{inner_block: fn _changed, _argument -> "Content" end}]
    )
  end

  defp anonymous_account do
    %AccountControl{
      kind: :sign_in,
      label: "Sign In",
      profile_path: nil,
      settings_path: nil
    }
  end
end
