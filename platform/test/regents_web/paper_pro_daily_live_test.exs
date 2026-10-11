defmodule RegentsWeb.PaperProDailyLiveTest do
  use RegentsWeb.ConnCase, async: false

  alias Regents.Repo

  import Regents.PaperProDailyFixtures

  setup do
    Repo.delete_all("paper_pro_daily_papers")
    :ok
  end

  test "future content is absent from static HTML and the connected page", %{conn: conn} do
    today = paper_fixture!(Date.utc_today())
    future = paper_fixture!(Date.add(today.date, 1), %{title: "Unreleased secret title"})

    html = conn |> get("/paper-pro-daily") |> html_response(200)
    assert html =~ today.title
    refute html =~ future.title
    refute html =~ future.answer

    {:ok, view, html} = live(conn, "/paper-pro-daily")
    assert has_element?(view, "#papers-#{today.date}")
    refute has_element?(view, "#papers-#{future.date}")
    refute html =~ future.title
    refute html =~ future.answer
  end

  test "midnight refresh updates an open feed and resets pagination coherently", %{conn: conn} do
    today = Date.utc_today()
    older = Enum.map(1..7, &paper_fixture!(Date.add(today, -&1)))
    future = paper_fixture!(Date.add(today, 1))
    {:ok, view, _html} = live(conn, "/paper-pro-daily")

    render_hook(view, "load_more", %{})
    assert has_element?(view, "#papers-#{List.last(older).date}")

    # Exercise the timer handler without sleeping or changing the host clock.
    # The exact clock boundary is covered by PaperProDailyTest.
    current = paper_fixture!(today)
    send(view.pid, :publication_midnight)

    assert has_element?(view, "#papers-#{current.date}")
    refute has_element?(view, "#papers-#{future.date}")
    assert has_element?(view, "#paper-daily-more[data-cursor='6']")

    render_hook(view, "load_more", %{})

    for paper <- [current | older] do
      assert has_element?(view, "#papers-#{paper.date}")
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

  test "direct scheduled picture URLs return non-cacheable 404 responses", %{conn: conn} do
    current = paper_fixture!(Date.utc_today())
    future = paper_fixture!(Date.add(current.date, 1))

    for suffix <- ["", "?v=guessed"] do
      response = get(conn, "/paper-pro-daily/pictures/#{future.date}#{suffix}")
      assert response(response, 404) == "Not found"
      assert get_resp_header(response, "cache-control") == ["no-store"]
    end

    response = get(conn, "/paper-pro-daily/pictures/#{current.date}")
    assert response(response, 200) == current.picture
    assert get_resp_header(response, "content-type") == ["image/png"]
  end
end
