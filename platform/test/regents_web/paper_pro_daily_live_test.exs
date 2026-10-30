defmodule RegentsWeb.PaperProDailyLiveTest do
  use RegentsWeb.ConnCase, async: false

  import Regents.PaperProDailyFixtures

  test "future content is absent from static HTML and the connected page", %{conn: conn} do
    today = paper_fixture!(Date.utc_today())
    future = paper_fixture!(Date.add(today.date, 1), %{title: "Unreleased secret title"})

    html = conn |> get("/paper-pro-daily") |> html_response(200)
    assert html =~ today.title
    refute html =~ future.title
    refute html =~ future.answer

    {:ok, view, html} = live(conn, "/paper-pro-daily")
    assert has_element?(view, "#days-#{today.date}")
    refute has_element?(view, "#days-#{future.date}")
    refute html =~ future.title
    refute html =~ future.answer
  end

  test "midnight refresh updates an open feed and resets pagination coherently", %{conn: conn} do
    today = Date.utc_today()
    older = Enum.map(1..7, &paper_fixture!(Date.add(today, -&1)))
    future = paper_fixture!(Date.add(today, 1))
    {:ok, view, _html} = live(conn, "/paper-pro-daily")

    render_hook(view, "load_more", %{})
    assert has_element?(view, "#days-#{List.last(older).date}")

    # Exercise the timer handler without sleeping or changing the host clock.
    # The exact clock boundary is covered by PaperProDailyTest.
    current = paper_fixture!(today)
    send(view.pid, :publication_midnight)

    assert has_element?(view, "#days-#{current.date}")
    refute has_element?(view, "#days-#{future.date}")
    assert has_element?(view, "#paper-daily-more[data-cursor='6']")

    render_hook(view, "load_more", %{})

    for paper <- [current | older] do
      assert has_element?(view, "#days-#{paper.date}")
    end

    refute has_element?(view, "#paper-daily-more")
    refute render(view) =~ future.answer
  end

  test "a feed containing only scheduled papers remains empty", %{conn: conn} do
    future = paper_fixture!(Date.add(Date.utc_today(), 1))
    {:ok, view, html} = live(conn, "/paper-pro-daily")

    refute has_element?(view, "#paper-daily-list > li")
    refute has_element?(view, "#paper-daily-more")
    refute html =~ future.title
    refute html =~ future.answer
  end

  test "choosing tags narrows the list, keeps the choice in the address and copies only those papers",
       %{conn: conn} do
    today = Date.utc_today()
    swarm = paper_fixture!(today, %{title: "Swarm paper", tags: ["Swarms"]})
    safety = paper_fixture!(Date.add(today, -1), %{title: "Safety paper", tags: ["Safety"]})
    both = paper_fixture!(Date.add(today, -2), %{title: "Both paper", tags: ["Safety", "Memory"]})
    {:ok, view, _html} = live(conn, "/paper-pro-daily")

    assert has_element?(view, ".paper-daily__filtered--off[inert] #paper-daily-copy-filtered")

    view |> element("#paper-daily-tag-safety") |> render_click()
    assert_patch(view, "/paper-pro-daily?tags=Safety")
    assert has_element?(view, "#paper-daily-tag-safety[aria-pressed='true']")
    assert has_element?(view, "#days-#{safety.date}")
    assert has_element?(view, "#days-#{both.date}")
    refute has_element?(view, "#days-#{swarm.date}")
    refute has_element?(view, "#paper-daily-research-list", swarm.title)

    copied = filtered_markdown(view)
    assert copied =~ "# Paper Pro Daily: Safety"
    assert copied =~ "## Safety paper"
    assert copied =~ "Tags: Safety, Memory"
    refute copied =~ swarm.title

    # A second tag adds its papers; the entire-page copy always holds every paper.
    view |> element("#paper-daily-tag-swarms") |> render_click()
    assert_patch(view, "/paper-pro-daily?tags=Swarms%2CSafety")
    assert filtered_markdown(view) =~ swarm.title
    assert view |> element("#paper-daily-copy-page") |> render() =~ "Safety paper"

    view |> element("#paper-daily-tag-swarms") |> render_click()
    view |> element("#paper-daily-tag-safety") |> render_click()
    assert_patch(view, "/paper-pro-daily")
    assert has_element?(view, "#days-#{swarm.date}")
    assert has_element?(view, ".paper-daily__filtered--off[inert]")
  end

  test "a shared address opens with its tags chosen and leaves out unknown ones", %{conn: conn} do
    today = Date.utc_today()
    memory = paper_fixture!(today, %{tags: ["Memory"]})
    swarm = paper_fixture!(Date.add(today, -1), %{tags: ["Swarms"]})

    {:ok, view, _html} = live(conn, "/paper-pro-daily?tags=Memory,Gossip")
    assert has_element?(view, "#paper-daily-tag-memory[aria-pressed='true']")
    assert has_element?(view, "#days-#{memory.date}")
    refute has_element?(view, "#days-#{swarm.date}")

    {:ok, view, _html} = live(conn, "/paper-pro-daily?tags=Economics")
    assert render(view) =~ "No papers with these tags."
    refute has_element?(view, "#paper-daily-list > li")
  end

  defp filtered_markdown(view) do
    [copied] =
      view
      |> element("#paper-daily-copy-filtered")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("data-copy-text")

    copied
  end

  test "direct scheduled picture URLs return non-cacheable 404 responses", %{conn: conn} do
    current = paper_fixture!(Date.utc_today())
    future = paper_fixture!(Date.add(current.date, 1))

    for suffix <- ["", "?v=guessed"] do
      response = get(conn, "/paper-pro-daily/pictures/#{future.id}#{suffix}")
      assert response(response, 404) == "Not found"
      assert get_resp_header(response, "cache-control") == ["no-store"]
    end

    response = get(conn, "/paper-pro-daily/pictures/#{current.id}")
    assert response(response, 200) == current.picture
    assert get_resp_header(response, "content-type") == ["image/png"]
  end
end
