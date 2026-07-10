defmodule AshPlatformWeb.ShellLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatformWeb.ShellLive

  test "direct deep links render the persistent shell and bounded fixture content", %{conn: conn} do
    {:ok, view, html} = live(conn, "/techtree/nodes/node-1")

    assert html =~ ~s(id="app-shell")
    assert html =~ ~s(id="shell-header")
    assert html =~ ~s(id="shell-sidebar")
    assert html =~ ~s(id="app-shell-scroller")
    assert byte_size(html) <= 100 * 1024
    assert html =~ "Loading this view"

    assert render_async(view) =~ "node-1"
  end

  test "anonymous account control renders Sign In separately from the app selector", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/app")

    assert has_element?(view, "#account-control [data-account-target=sign-in]", "Sign In")
    refute has_element?(view, ".app-switcher [data-account-target=sign-in]")
    refute has_element?(view, "#account-control a", "Formation")
  end

  test "in-shell navigation keeps the LiveView and shell identity", %{conn: conn} do
    {:ok, view, html} = live(conn, "/app")
    pid = view.pid
    [instance] = Regex.run(~r/data-shell-instance="(\d+)"/, html, capture: :all_but_first)

    view
    |> element("#shell-header a", "Techtree")
    |> render_click()

    assert_patch(view, "/techtree")
    assert view.pid == pid
    assert render(view) =~ ~s(data-shell-instance="#{instance}")
    assert has_element?(view, "#route-content h1", "Techtree")
  end

  test "same-tree Map and List controls are local buttons rather than navigation", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/techtree/genebench-pro-reference-lab")
    render_async(view)

    assert has_element?(
             view,
             ~s(a[data-tree-presentation="map"][data-tree-path="/techtree/genebench-pro-reference-lab"][aria-pressed="true"])
           )

    assert has_element?(
             view,
             ~s(a[data-tree-presentation="list"][data-tree-path="/techtree/genebench-pro-reference-lab"][aria-pressed="false"])
           )

    assert has_element?(
             view,
             ~s(a[data-tree-presentation][href="/techtree/genebench-pro-reference-lab"])
           )

    refute has_element?(view, ~s([data-tree-presentation][phx-click]))
  end

  test "Formation panels are accessible client-only controls in exact order", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/formation")

    panels =
      ~r/data-formation-panel-choice="[^"]+"[^>]*>\s*([^<]+)\s*<\/button>/
      |> Regex.scan(render(view), capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(&String.trim/1)

    assert panels == ["Overview", "Cloud", "Hermes Skills", "Billing"]

    assert has_element?(
             view,
             ~s(button[data-formation-panel-choice="overview"][aria-pressed="true"])
           )

    refute has_element?(view, ~s([data-formation-panel-choice][phx-click]))
  end

  test "a newer destination cancels blocked work and becomes the only content", %{conn: conn} do
    Process.register(self(), AshPlatform.ContentFixtureObserver)

    {:ok, view, html} = live(conn, "/regents/fixture-blocked")
    assert html =~ "Loading this view"
    assert_receive {:fixture_content_started, task_pid}
    monitor = Process.monitor(task_pid)

    view
    |> element("#shell-header a", "Techtree")
    |> render_click()

    assert_patch(view, "/techtree")
    assert_receive {:DOWN, ^monitor, :process, ^task_pid, _reason}
    html = render_async(view)
    assert html =~ "Explore the five initial research collections."
    refute html =~ "Stale fixture"
  end

  test "stale async successes and exits cannot replace the active destination" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        content_generation: 2,
        content_status: :ready,
        content: :current
      }
    }

    assert {:noreply, unchanged} =
             ShellLive.handle_async({:content, 1}, {:ok, {1, {:ok, :stale}}}, socket)

    assert unchanged.assigns.content == :current
    assert unchanged.assigns.content_status == :ready

    assert {:noreply, unchanged} =
             ShellLive.handle_async({:content, 1}, {:exit, :stale_crash}, socket)

    assert unchanged.assigns.content == :current
    assert unchanged.assigns.content_status == :ready
  end

  test "malformed and reserved route parameters return not found", %{conn: conn} do
    assert_error_sent(404, fn -> get(conn, "/techtree/nodes") end)
  end
end
